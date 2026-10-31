-- sv_config.lua: the difficulty, CFG (every setting) and survival.ini.
-- Part of AC8 Survival Mode's runtime, run by main.lua in order (sv_core, sv_config, sv_rows, sv_ai, sv_hud, sv_sound, sv_spawn, sv_anomalies, sv_rounds, sv_ladon, sv_leaderboard, sv_alicorn, sv_amphib, sv_flights, sv_shop, sv_allies, sv_tactical, sv_main); a name
-- another part uses is a global of this mod's Lua state, its own helpers stay local (tools/lua_split.py).

-- The game's current difficulty (LiveDifficultyManager.CurrentDifficulty: 1 Casual .. 5 Ace).
local DIFFICULTY = { [0] = "None", "Casual", "Easy", "Normal", "Hard", "Ace", "FreeFlight" }
function logDifficulty(when)
    local dm = FindFirstOf("LiveDifficultyManager")
    local ok, d = pcall(function() return dm.CurrentDifficulty end)
    log("difficulty " .. when .. ": " .. ((ok and type(d) == "number") and (DIFFICULTY[d] or tostring(d)) or "unknown"))
end

levelTick = nil              -- tick count when Survival's level was loaded (nil again once the run is over)
pcall(NotifyOnNewObject, "/Script/Engine.World", function(w)
    local n = nameOf(w)
    if n:find("PL_SurvivalMode", 1, true) then levelTick = -1 end      -- picked up by the next tick
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
    log = { verbose = false },
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
            reaper = { turn_add = { pitch = 180, roll = 360, yaw = 45 }, speed_x = 1.25, cruise_x = 1.15,
                       health_add = 600, post_stall = true, hunt = true, no_provoke = true, moves = true,
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
    special = { enabled = true,
                fcs = { "NPC_FCS_PlaneQAAM000", "NPC_FCS_Plane2AAM000", "NPC_FCS_PlaneLAAM000", "NPC_FCS_PlaneHCAA000" } },
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
    -- airstrike_x.
    credits = {
        start = 0, fighter = 100, bomber = 200, heavy = 400, round_bonus = 250, special_x = 2.0,
        round_x_per_round = 0.02, round_x_max = 1.5, ally_x = 0.5, airstrike_x = 0.5,
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
            -- tactical items, carried until used, at most `max` of each (CFG.tactical: how they work)
            Airstrike  = { role = "tactical", tac = "airstrike", label = "AIRSTRIKE", price = 6000, raise = 1.0, max = 2 },
            Ecm        = { role = "tactical", tac = "ecm", label = "ECM BURST", price = 4000, raise = 1.0, max = 2 },
            Decoy      = { role = "tactical", tac = "decoy", label = "DECOY", price = 4000, raise = 1.0, max = 2 },
            -- one shoot-down survived (CFG.insurance), one held at a time ("insurance as a high-end purchase")
            Insurance  = { role = "insurance", label = "SECOND CHANCE", price = 50000, raise = 1.0 },
            -- a cheaper first rung of allies ("a pair of F-16s for about 5,000 before MOONCHILD at 15,000"): flies on
            -- MOONCHILD's two flights (CFG.allies.wingmen), so at most two flights of the two kinds are up together
            Wingmen    = { role = "ally_air", ally = "wingmen", label = "SNIPER: 2 x F-16C, LAAMs", price = 5000, raise = 1.2 },
            -- VOID WATCHER 1 (CFG.allies.awacs): an E-767 AWACS that takes off from the airfield and orbits it, its ESM
            -- field over the whole airfield; one up at a time
            VoidWatcher = { role = "ally_awacs", label = "VOID WATCHER 1: E-767 AWACS", price = 12000, raise = 1.0 },
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
                             fcs = { lock_x = 0.75, fire_x = 0.5, range_x = 2.0, search_m = 10000, slew_x = 2.0, yaw_full = true,
                                     round_reach = true, round_width_x = 1.5,
                                     missile = { range_m = 8000, life_s = 14, accel_x = 2.0, speed_max_kmph = 3600, turn_x = 1.5 } },
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
        -- parking spot and scramble, then an orbit 7 km round the airfield, 4.5 km up; it never fights, enemies may
        -- hunt it). Its ESM (BP_wp_esm_MS28, a LiveElectronicSupportMeasures field round it; the AI never switches it on
        -- by itself) is fired every esm.every_s while it's airborne (RE_SV_AwacsEsm), each field set to esm.range_m
        -- (stock 3.2 km) for esm.life_s; its fire control's reach esm.capture_m. scale: as MOONCHILD's (health only:
        -- it has no weapons).
        awacs        = { enabled = true, name = "VOID WATCHER 1", name_key = "SV_VoidWatcher", unit = "SV_Unit_VoidWatcher",
                         row = "SV_Ally_VoidWatcher",
                         esm = { event = "RE_SV_AwacsEsm", every_s = 20, range_m = 25000, life_s = 24, capture_m = 60000,
                                 class = "BP_wp_esm_MS28_C" },
                         scale = { rank_add = 0, rank_min = 3, ai_level_min = 3, health_x = 3.0, health_per_round = 0.08,
                                   health_max_x = 6.0 } },
        ships        = {
            -- search_m: its turrets' AI module (a copy of NPC_AIModule_Turret000, 6000 m, made NPC_AIModule_SV_<key>),
            -- the farthest they see anything, and no losing targets in cloud. missile: its homing missiles' own weapon
            -- row (VLS_Vessel_000: 9 s of flight from 500 km/h, +300 km/h a second to 3000, ~4 km, so 6 km locks fell
            -- short; user, 2026-10-23: "aegis ships still don't engage far enough"): lock-on at range_m, life_s of
            -- flight, acceleration x accel_x, top speed speed_max_kmph, turn rate x turn_x.
            -- health_add: HP on its hull's own (economy review: "ships placed to protect"; its row's MaxHealthDifference)
            Aegis = { name = "DDG AEGIS", turrets = "aegs", health_add = 300,
                      fcs = { lock_x = 0.5, fire_x = 0.5, range_x = 2.0, search_m = 25000,
                                                  missile = { range_m = 20000, life_s = 30, accel_x = 2.0,
                                                              speed_max_kmph = 3600, turn_x = 1.5 } },
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
    --   airstrike: the enemy flight with the most aircraft within range_km of you (no specials, no aces leading)
    --              destroyed delay_s after the call; its kills pay CFG.credits.airstrike_x. auto: when auto_near or more
    --              enemies are within auto_km of you.
    --   ecm:       for ecm_s every enemy missile within range_km of you loses its lock (homing off; one still closing
    --              within kill_m is destroyed). auto: when auto_missiles or more are within auto_km of you.
    --   decoy:     the enemy fighter flight nearest you breaks off for decoy_s (RE_SV_Decoy_NN: no engagement), then
    --              comes back (RE_SV_DecoyEnd_NN: its orders again). auto: a flight of auto_size or more within auto_km.
    tactical = { keys = true,
                 airstrike = { delay_s = 4, range_km = 15, auto = true, auto_near = 8, auto_km = 10 },
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
              timeout_s = 0, callout = true },
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
               ecm = true, ecm_every_s = 14 },
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
    -- fighter flights sent after the joiner (the stock allied-hunt order). leaderboard: co-op runs aren't sent.
    -- max_players: the host's room, 2 to 24 (you included; user, 2026-10-26: "allow up to 24 players in a lobby ... leave
    -- it there for choice"); joiners link to the host only, which relays their planes. The host down at the airfield
    -- holds the new enemies only while nobody else flies (user, 2026-10-29: "the game isn't paused for the other
    -- players"; sv_rounds.lua othersFlying).
    coop = { enabled = false, role = "auto", transport = "steam", partner = "auto", port = 27777, interp_ms = 120, max_players = 24,
             split_share = 0.5, callouts = true, leaderboard = false,
             -- each other player as their own airframe's player plane, as AC8's Online Mode shows them (COOP2MP T3,
             -- tools/re/COOP2MP.md); false: an AI stand-in of their airframe, as 0.72 (also the fallback)
             real_planes = true,
             -- real_damage: their damage shown on their real plane (its health as their game says, never under 1 HP)
             real_damage = true,
             -- join_wait_s: the host's round waits (no round start, no spawns) while a linked player isn't in the mission
             -- yet, each at most this long; 0: never
             join_wait_s = 90,
             -- migration (the user, 2026-10-31: "if the Host does leave, it automatically tries to find the next best
             -- host"): when the host's game goes, the player with the best link takes over as host and the others join
             -- them; the round in play starts again, the allies and the airfield's defences are built again. after_s:
             -- the host silent this long first (longer while it said it's reloading: a run's end); link_s: each next
             -- host waited for; wait_s: the new host's round held this long for everyone to be back; break_s: its break.
             -- Steam only (each player's Steam ID).
             migration = { enabled = true, after_s = 30, link_s = 20, wait_s = 60, break_s = 15 },
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
             -- so what they fire only shows; enabled = false: none of it, and their airframes' own rows as before
             sync = { enabled = true, missiles = true, guns = true, flares = true, gear = true, afterburner = true,
                      ab_throttle = 0.9 },
             -- revives (Scripts/sv_down.lua, tools/re/COOP.md 9; user, 2026-10-29: "if you die, HOST or JOINER, someone
             -- could land at the airfield and buy you back ... you get put into a spectator camera and you can switch
             -- between the players currently active"). Co-op only: your plane is held at floor_hp; there you're DOWN,
             -- flown round the airfield (loiter: alt_m up, radius_m round) and watch another player; any other player at
             -- their airfield buys you back from the STORE's AIRFIELD page for price, x raise for each revive in the run
             -- (the host's count), and you're back repaired, safe_s seconds invincible, where the loiter left you
             -- (respawn "loiter"; farther than near_km from the airfield: "native" instead) or 4 km out from the runway at 500 m
             -- ("native"). Everyone down: the run's over.
             -- down_round_bonus: a downed player still gets the round bonuses. key / ctrl: the next player to watch;
             -- camera: back_m behind and up_m above the plane you watch, blend_s to swing over. key, ctrl and camera
             -- are each player's own, the rest the host's.
             revive = { enabled = true, floor_hp = 0.1, price = 2500, raise = 1.25, safe_s = 5,
                        loiter = { alt_m = 2500, radius_m = 4000 }, respawn = "loiter", near_km = 8, drift_km = 10, key = "O", ctrl = false,
                        camera = { back_m = 30, up_m = 8, blend_s = 0.5 }, down_round_bonus = true } },
    -- Special rounds (Milestone 6): from round `first`, every `every` rounds, the next special of `rotation` instead of a
    -- normal round (a special that can't start falls back to one). "shuttle" = Comona Defense
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
    specials = {
        enabled  = true,
        random   = true,
        chance   = 0.3,
        first    = 4,
        every    = 5,
        rotation = { "shuttle", "anomaly", "amphibious", "ladon", "alicorn", "glitch", "valka" },
        -- an early special (user, 2026-10-23: "buff the chances of the shuttle spawning between rounds 2 and 6"): in
        -- rounds from .. to, each round is `kind` with `chance` (before `first` too), under the same rules (never two
        -- specials in a row, not the same one twice running), and no other special comes in those rounds: the
        -- random picks above start after `to` (user: only the Shuttle Launch may come between 2 and 6).
        early    = { kind = "shuttle", from = 2, to = 6, chance = 0.35 },
        -- each special comes at most once in this many rounds (user, 2026-10-23): Comona Defense in round 2 can come
        -- again from round 12; the others keep their chance meanwhile. 0: no cooldown.
        cooldown_rounds = 10,
        -- specials scale with the round (economy review of 2026-10-25: "all five were beaten easily, in 2.8-4.4 minutes.
        -- A special late in the run should bring escorts and more health, like the normal rounds around it"): from
        -- escort_from, the specials named in escort_kinds (which fly alone) bring escort_share of the round's aircraft
        -- as fighter flights (escort_min..escort_max). Their health grows by their own health_per_round.
        -- Not the Ladons (user, 2026-10-25: "during a ladon round, only the ladon's spawn, no other aircraft should").
        escort_from = 12, escort_share = 0.25, escort_min = 2, escort_max = 8,
        escort_kinds = { "alicorn", "glitch" },
        -- "alicorn" = the ALICORN (tools/survival_events.py ALCN_*; tools/re/ALICORN.md; user, 2026-10-23: "start
        -- working on the ALICORN special round ... spawn none of the normal aircraft"): Online Mode's submarine
        -- carrier, without the fighters and drones it launches there, sailing the west sea. It dives every
        -- dive_every_s for dive_for_s, and while surfaced fires its railgun every railgun_every_s and a VLS volley at
        -- you every volley_every_s. Destroy its four ballast tanks and the core opens; destroy the core to sink it.
        -- Its parts' health x health_x (tuned for an online squad) and health_per_round more a round after `first`.
        -- Each ballast tank takes tank_missiles of your standard missiles (user, 2026-10-23: "it should only take like
        -- 6 missiles to destroy each ballast tank"; 14 missiles took none down), from the missile's own damage read in
        -- game, more a round as above; health_x when it can't be read. 0: health_x. Its weapons (weapon_classes: the
        -- VLS, SAM, AA guns, CIWS, ECM and their hatches) take weapon_missiles each, its railguns railgun_missiles
        -- (user, 2026-10-23: "lower the health down on the alicorns weaponry"; they had the online squad's 800-2000 and
        -- took 10-62.5 % from most weapons); never more than they had. 0: their online health.
        -- Its rows are Online Mode's (DT_SV_Alcn*): `tables` adds them to the campaign tables at the main menu.
        -- Debuffed across the board (user, 2026-10-23: "way too strong"; were 110 / 30 / 25 / 35 / 25, health x0.5,
        -- +0.04 a round, at most x1.5): shorter dives, its first shot later, railgun and volleys less often, less health.
        -- (health_per_round 0.05, health_max_x 1.4: were 0.03 / 1.0, economy review of 2026-10-25)
        -- It counts as surfaced once it's back within surfaced_m of where it sailed (the order sent again every
        -- resurface_s while it isn't rising, resurface_tries times at most; up anyway after up_wait_s).
        -- rail_alert (behaviour roadmap P3/P7, tools/re/BEHAVIOUR_DIRECTOR.md unit 4): Mission 18's RAILGUN WARNING on
        -- every game (RE_SV_AlcnAlertOn, forwarded) with the railgun's tell (CFG.tells alcn_rail, its lead_s before the
        -- order), off alert_s after the order (it aims ~7 s and preps ~2 s: tools/re/ALICORN.md), at a dive and when it
        -- sinks (hard rule 45); false: no warning (the tell still comes with tells on). After a surfacing the warning
        -- comes no sooner than radio_gap_s after "submarine has surfaced" (the order its lead after it). Once you've
        -- destroyed both railguns: the warning off, no more warnings, tells or orders; every VLS: no more VLS calls or
        -- volleys (code review of 2026-10-29)
        -- deck (behaviour roadmap P7, "surfaced phase spawns Skirmishers from its deck"; tools/re/BEHAVIOUR_DIRECTOR.md
        -- unit 9): while it's up it launches fighters: a free pool flight of `size` (the Skirmishers' own with the fighter
        -- roles on, CFG.roles; else any) spawned alt_m above it, ahead_m off its bow, along its heading (Survival's spawner
        -- with a pose, not Online Mode's launches, whose pooled fighters stay put away; never one of the round's own
        -- flights still to come). The first first_s after it appears, then every every_s, and after_surface_s after each
        -- surfacing; warn_s before each its radio call (CFG.tells alcn_deck), only once the launch can go
        -- (a launch held is told again warn_s before it goes; another tell's gap holds it a second, twice at most); never
        -- more than max_up of its flights up at once, never while you're down at the airfield (a flight that appears in
        -- the landing menu gets no orders) but on a co-op host while another player flies (sv_rounds.lua othersFlying;
        -- ordersTick gives it its orders). alt_m: at least 1100 (the pool's 2-ship units fly 1000 m and up: survival
        -- WD's MinAltitudeInMeter, code review of unit 9). A round's launches: `flights` + flights_per_round x the round,
        -- at most max_flights; from specials.escort_from its escorts come off the deck too (escorts: their aircraft in
        -- flights of `size`, none from a spawn point). false: no launches (its escorts as before)
        alicorn = { name = "ALICORN", dive_every_s = 120, dive_for_s = 20, first_shot_s = 40, railgun_every_s = 60,
                    surfaced_m = 3, resurface_s = 8, resurface_tries = 4, up_wait_s = 60,
                    rail_alert = { enabled = true, alert_s = 12 },
                    deck = { enabled = true, first_s = 25, every_s = 35, after_surface_s = 6, warn_s = 3, size = 2,
                             max_up = 2, flights = 2, flights_per_round = 0.15, max_flights = 6, escorts = true,
                             alt_m = 1200, ahead_m = 800 },
                    volley_every_s = 45, health_x = 0.3, health_per_round = 0.05, health_max_x = 1.4,
                    tank_pay = 500, reward = 12000, reward_per_round = 400, tank_missiles = 6,
                    weapon_missiles = 3, railgun_missiles = 4,
                    weapon_classes = {   -- its weapons and their hatches: which *_missiles each takes
                        BP_BA002_alcn_hatch_emls_L_Base_C = "railgun_missiles", BP_BA002_alcn_hatch_emls_R_Base_C = "railgun_missiles",
                        BP_BA002_alcn_emls_Base_C = "railgun_missiles",
                        BP_BA002_alcn_vlsL1_Base_C = "weapon_missiles", BP_BA002_alcn_vlsL2_Base_C = "weapon_missiles",
                        BP_BA002_alcn_vlsR1_Base_C = "weapon_missiles", BP_BA002_alcn_vlsR2_Base_C = "weapon_missiles",
                        BP_BA002_alcn_vls_Base_C = "weapon_missiles", BP_BA002_alcn_ecm_Base_C = "weapon_missiles",
                        BP_BA002_alcn_hatchL1_Base_C = "weapon_missiles", BP_BA002_alcn_hatchL2_Base_C = "weapon_missiles",
                        BP_BA002_alcn_hatchL3_Base_C = "weapon_missiles", BP_BA002_alcn_hatchL4_Base_C = "weapon_missiles",
                        BP_BA002_alcn_hatchL5_Base_C = "weapon_missiles", BP_BA002_alcn_hatchL6_Base_C = "weapon_missiles",
                        BP_BA002_alcn_hatchR1_Base_C = "weapon_missiles", BP_BA002_alcn_hatchR2_Base_C = "weapon_missiles",
                        BP_BA002_alcn_hatchR3_Base_C = "weapon_missiles", BP_BA002_alcn_hatchR4_Base_C = "weapon_missiles",
                        BP_BA002_alcn_hatchR5_Base_C = "weapon_missiles", BP_BA002_alcn_hatchR6_Base_C = "weapon_missiles",
                        BP_BA002_alcn_aagun_Base_C = "weapon_missiles", BP_BA002_alcn_ram_Base_C = "weapon_missiles",
                        BP_BA002_alcn_ciws_Base_C = "weapon_missiles", BP_BA002_alcn_ciwsp5_Base_C = "weapon_missiles" },
                    tank_classes = { "BP_BA002_alcn_btankfl_Base_C", "BP_BA002_alcn_btankfr_Base_C",
                                     "BP_BA002_alcn_btankrl_Base_C", "BP_BA002_alcn_btankrr_Base_C" },
                    core_class = "BP_MP028_dummy_emlmcore_Base_C",
                    tables = { { "/Game/Mods/SurvivalMode/Data/DT_SV_AlcnNpc.DT_SV_AlcnNpc", "/Game/Datatables/AI/NPC/DT_NPC.DT_NPC" },
                               { "/Game/Mods/SurvivalMode/Data/DT_SV_AlcnModel.DT_SV_AlcnModel",
                                 "/Game/Datatables/AI/NPC/Model/DT_NPC_Model.DT_NPC_Model" },
                               { "/Game/Mods/SurvivalMode/Data/DT_SV_AlcnWpDur.DT_SV_AlcnWpDur",
                                 "/Game/Datatables/AI/NPC/WeaponDurability/DT_NPC_WeaponDurability.DT_NPC_WeaponDurability" },
                               { "/Game/Mods/SurvivalMode/Data/DT_SV_AlcnExDur.DT_SV_AlcnExDur",
                                 "/Game/Datatables/AI/NPC/ExplosionDurability/DT_NPC_ExplosionDurability.DT_NPC_ExplosionDurability" } } },
        -- "glitch" = AB.L..IN, squadron tag IFF: FATAL ERROR (user, 2026-10-23: "One Last Anomaly. an EA-18G Growler, It's
        -- health is set to 450. it has ECM Activated always, it's a normal aircraft, but as soon as it gets damaged, it
        -- begins to teleport at different angles, during this time, it's constantly firing it's gun at you ... for 6
        -- seconds before continuing to flight normally against you ... disappear in a small smoke cloud, also have it
        -- reappear within small smoke clouds too"; "it teleports around the player ... fully aiming at the player as
        -- it fires it's gun with extreme accuracy"). One EA-18G alone (tools/survival_events.py GLITCH_*), `health`
        -- HP (the EA-18G has 60), its ECM pod always up, an accurate gun that holds the trigger (gun_*: it fires once
        -- you're within gun_range_m and gun_angle_deg of its nose). It arrives hidden and shows in a puff of `smoke`
        -- arrive_s later. Each time it's hit (outside a frenzy) it frenzies for frenzy_s: every blink_every_s it
        -- vanishes in smoke (hidden, untargetable, unhurt) and comes back in smoke at one of the `blinks` spots around
        -- you at your height (user: "at whatever height the player is closest too"), one at least ground_clear_m above
        -- the ground, at least blink_turn_deg round you from the last one, and its gun is fired at you all
        -- through it (gun_every_s). Its health grows health_per_round a round after `first` (at most
        -- health_max_x), as the other specials'. Shot down: `reward` zollars.
        -- (health_per_round 0.06, health_max_x 3.5: were 0.04 / 3.0, economy review of 2026-10-25)
        glitch   = { name = "AB.L..IN", squadron = "IFF: FATAL ERROR", unit = "SV_Unit_Glitch", health = 450,
                     reward = 7000, reward_per_round = 250, ai_level = 5, spawn_km = { 6, 9 }, arrive_s = 1.0,
                     health_per_round = 0.06, health_max_x = 3.5,
                     frenzy_s = 6, blink_every_s = 1.0, blink_turn_deg = 60, ground_clear_m = 150,
                     -- its gun and ECM pod on command (tools/survival_events.py GLITCH_GUN_* / _ECM_SLOT): through a
                     -- frenzy RE_SV_GlitchGun every gun_every_s, which fires the gun at you 5 times 0.1 s apart (user,
                     -- 2026-10-23: "make it fire at 0.1"; = GLITCH_GUN_SHOTS x GLITCH_GUN_EVERY_S, keep in step); the
                     -- pod every ecm_every_s while it's up
                     gun_every_s = 0.5, ecm_every_s = 14,
                     -- its blink spots: the event package's (tools/survival_events.py GLITCH_BLINK_*; keep in step, not
                     -- an ini setting): RE_SV_GlitchBlink_<ring letter><bearing letter>, every step_deg on each ring
                     blinks = { step_deg = 30, rings_m = { 500, 800 } },
                     gun_range_m = 1500, gun_angle_deg = 6, gun_damage_x = 1.5, gun_spread_deg = 0.1,
                     -- it leads you as MINDRIPPER does (user, 2026-10-24): gun_lead_s ahead; 0.8 s suits its blinks
                     -- 500 / 800 m from you (its rounds fly 833 m/s). Its own fire control leads by its row; in a frenzy
                     -- (user: "go through the mission event the EA-18G uses and see if you can find gun lead for it": the
                     -- event's LiveFireOneShotWeapon only aims at the target) Lua also fires it each tick gun_lead_shots
                     -- times with LiveAIGameObject.FireOneShotWeaponWithLocationTracking at where you'll be gun_lead_s on
                     -- (your velocity); gun_lead_event: the event's unled shots go on as well (false: only the led ones)
                     gun_lead_s = 0.8, gun_lead_shots = 2, gun_lead_event = true,
                     -- post-stalls on command (user, 2026-10-24: "make the EA-18G do post stalls even more"): outside
                     -- a frenzy, within post_stall_range_km of you, one of post_stall_moves (tools/survival_events.py
                     -- GLITCH_POST_STALL: Shadow / Toprak kulbits, Tasha's cobra) every post_stall_every_s, and as soon
                     -- as you get behind it (more than 110 deg off its nose within post_stall_behind_km), at least
                     -- post_stall_gap_s apart; its own cobra / kulbit are on whatever the round
                     post_stall = true, post_stall_every_s = 6, post_stall_gap_s = 3, post_stall_range_km = 3,
                     post_stall_behind_km = 1.5, post_stall_moves = { "Kulbit", "KulbitB", "Cobra" },
                     -- its phases (behaviour roadmap P7: "after two frenzies it starts blinking behind you, not just
                     -- around you; a third phase drops ECM and goes all-out guns"; tools/re/BEHAVIOUR_DIRECTOR.md unit 9).
                     -- Phase 2 once behind_after frenzies are over: behind_share of its blinks at the spot nearest your
                     -- six (your heading, at your height; the tell "glitch_six" first). Phase 3 at allout_hp of its health
                     -- (as it appeared): no more frenzies or blinks, its ECM pod down (no RE_SV_GlitchEcm; ecm_pods_off:
                     -- the pods up switched off, checked every ecm_check_s, on a co-op joiner's copy too; ecm_row: its own
                     -- pod's row refires it by itself at most once a minute, made at the main menu, a game restart to
                     -- change; off by default, code review of unit 9: hard rule 40's "up all fight" was confirmed with the
                     -- 14 s row and the event together, so phases 1-2 keep that until a test shows the 60 s row holds the
                     -- ECM up under the event alone), its gun at you whenever you're
                     -- within allout_range_km and allout_cone_deg of its nose (every allout_gun_s, led as a frenzy's), and
                     -- LastTGT onto you every allout_turn_s and at once (allout_behind_s apart) when you're behind it
                     -- within allout_behind_km (the tell "glitch_allout" first). false: one phase, as before
                     phases = { enabled = true, behind_after = 2, behind_share = 0.5, allout_hp = 0.35,
                                allout_range_km = 1.5, allout_cone_deg = 20, allout_gun_s = 0.5, allout_turn_s = 10,
                                allout_behind_s = 3, allout_behind_km = 3, ecm_row = false, ecm_pods_off = true,
                                ecm_check_s = 2 },
                     -- the dead flying (user: "look spooky like its the dead flying"): its airframe in the wreck's
                     -- burnt material, no pilot or stores, the damaged-plane smoke and fire on it
                     dead_look = true, dead_fx_scale = 1.0,
                     dead_material = "/Game/Vehicles/Aircraft/PP/PP0010_e18g/Materials/Common/MI_PP0010_e18g_DAM",
                     dead_fx = { "/Game/VFX/Vehicles/Aircraft/Common/Damage/DamagedSmokeNPC/NS_DamagedSmokeFireNPC001",
                                 "/Game/VFX/Vehicles/Aircraft/Common/Damage/DamagedSmokeNPC/NS_DamagedSmokeNPC001" },
                     smoke = "/Game/VFX/Vehicles/Aircraft/Common/Bailout/NS_BailoutSmoke001", smoke_scale = 4.0,
                     smoke_s = 3.0 },
        -- "valka" = VALKA (user, 2026-10-24: "port the Mihaly Fight from ACE7 into ACE8 Survival Mode as an Anomaly Boss,
        -- we're going to mix MINDRIPPER's abilities and ABELCAINS abilities into this new Anomaly called VALKA, who uses
        -- an EML"; tools/survival_events.py VALKA_*). AC7 Mission 18's opener: a hidden railgun of its own (eml_unit, the
        -- x40a's RailGun part alone, not her) placed once on the horizon ahead of you (your heading, level with you),
        -- opener_km from you at its shot
        -- (further out by what you fly towards it in the charge, at most opener_max_km), fixed there (user,
        -- 2026-10-24: "9km from me in a fixed position in the sky that the player was currently aiming at, she can't
        -- be attached to the aircraft at all"), at least opener_min_alt_m up; a flash of light there, the railgun
        -- WARNING and charge for charge_s, then one shot at you; it's removed eml_remove_s later. reveal_s after the
        -- shot she spawns where it came from, facing you, and the focus camera swings onto her (`camera`). Then a Super AI (the top fire-control level, ai_level, MINDRIPPER's attack pressure) on you
        -- alone, anywhere (user: "the AI after the initial shot will always target the player and go after the player
        -- also using the lastTGT psm ability"): LastTGT every turn_every_s and at once when you get behind her within
        -- behind_km (behind_gap_s apart), post-stalls (post_stall_*), blinks round you (AB.L..IN's: each hit outside a
        -- blink spell starts blink_s of them, one every blink_every_s, then blink_cooldown_s before the next spell), her
        -- railgun every railgun_every_s (railgun_charge_s of warning first) when you're within railgun_range_km and
        -- railgun_cone_deg of her nose, and every invert_every_s a chance of invert_chance that your controls scramble
        -- for invert_s (random_min..random_max of random_fx, as MINDRIPPER's field). Her railgun fires one round a
        -- shot (user, 2026-10-24: "Mission 26 has a 4 shot EML, I only want single shot": its part's TriggerCount and
        -- MagazineCapacity 3 -> single_shot). No AC7 voice lines, no invincibility (AC7 held Mihaly's health with
        -- SetMinHealth until a radio line; she has none). Shot down: `reward` zollars.
        -- Disguised (user, 2026-10-24: "she'll appear in a random normal round, so the players don't suspect anything
        -- ... have less enemies spawn ... once all those enemies are dead then the VALKA attack starts"): her round is
        -- called out as a normal one (ROUND n / HOSTILES INBOUND, the break before it too) with decoy_share of the
        -- round's aircraft (decoy_min..decoy_max), and lurk_s after the last of them is down her attack starts: the
        -- opener, then straight after the shot the camera and the HUD's anomaly_line and her name big (big_x). The
        -- forced WARNING is on from her round's start until she's down (user, 2026-10-24).
        -- enabled = false: she never comes, whatever `rotation` says (a build without her X-02S and AC7 sounds:
        -- tools/package_release.sh novalka)
        valka    = { enabled = true, name = "VALKA", squadron = "MIHALY'S SHADOW", unit = "SV_Unit_Valka", health = 900,
                     health_per_round = 0.04, health_max_x = 2.5, reward = 9000, reward_per_round = 300, ai_level = 5,
                     disguise = true, decoy_share = 0.5, decoy_min = 2, decoy_max = 6, lurk_s = 4,
                     anomaly_line = "CATASTROPHIC LEVEL ANOMALY", big_x = 2.0,
                     spawn_km = { 6, 9 }, arrive_s = 1.0,
                     -- opener_bearing: the compass bearing it's on from you (270 = always west; user, 2026-10-24: "have
                     -- it always at the west"); nil = straight ahead of you
                     opener_bearing = 270, opener_km = 14, opener_max_km = 30, opener_marker = true, opener_min_alt_m = 1500, charge_s = 6.0, reveal_s = 0.5, eml_remove_s = 4,
                     eml_unit = "SV_Unit_ValkaEml",
                     -- her parts (all four, her own RailGun too) held back again every hold_s: they never fire by
                     -- themselves, only her scripted shots (test of 2026-10-24: 38 hits on the airfield in 13 s)
                     hold_s = 5,
                     -- her X-02S (tools/x02s; "" = the x40a as it is) and its length (m)
                     model = "/Game/Mods/SurvivalMode/Valka/Model/SK_X02S_Valka", model_length_m = 19.6,
                     -- the X-02S turned model_yaw deg more than the x40a's body (if it flies sideways or backwards);
                     -- shot down, the x40a's wreck meshes kept hidden wreck_s so the X-02S falls
                     model_yaw = 0, wreck_s = 15,
                     -- her paint (SPC.V.PAINTS): 1 as built, 2 the stock F/A-18E skin's values, no dirt mask, 3 that
                     -- and a white Livemap, 4 / 5 as 2 / 3 with the parent's dirt mask, 6-8 tests (the F/A-18E's Livemap,
                     -- its textures, the engine grid), 9-11 AC8's general masters with ordinary textures (Live base, Live base
                     -- WPO, character base); test key Ctrl+9 cycles them
                     paint = 11,            -- (11: AC8's character master, ordinary textures: SPC.V.PAINTS)
                     -- her swing wings: unswept below sweep_kmh[1], swept above [2] (AC7's), a full travel in sweep_s
                     -- (0.67.1-0.67.6 had it off: its keys went in without the AC7 -> UE axis change, and her wings came
                     -- apart in game; tools/x02s/ue_import.py ue_quat converts them now)
                     sweep_anim = "/Game/Mods/SurvivalMode/Valka/Model/A_X02S_Valka_Sweep", sweep_kmh = { 800, 1000 },
                     sweep_s = 2.5, hit_radius_m = 10,
                     -- the opener's flash: flash_layers copies of it at once (its light adds up), flash_scale big (user,
                     -- 2026-10-24: "put that further away and turn its brightness up a lot ... it was quite hard to see")
                     flash = "/Game/VFX/Mission/Mission023/NS_ms23FarFlash", flash_scale = 12.0, flash_s = 3.0, flash_layers = 4,
                     -- the opener's light as AC7 Mission 18's lens flash (user, 2026-10-24: "rebuild the Effect that Mihaly
                     -- uses when it spawns in on Mission 18"; ms18_LensEffect1, tools/x02s builds it): screen-space billboard
                     -- elements { name, size (fraction of the screen) } on AC8's own flare, faded over life_s along AC7's
                     -- alpha curve (time fraction, alpha), intensity_x times the stock flare's brightness. If it doesn't
                     -- load, the flash above shows instead.
                     -- her portal (user, 2026-10-24: "an event horizon black hole that Valka will spawn out of"): opens
                     -- lead_s before the opener's shot where she comes out, open_s / hold_s / close_s; sizes x diameter_m,
                     -- which grows to at least min_deg wide from where you are:
                     -- the lensing (lens_x the barrier refraction's strength), the glow and photon ring (their brightness x
                     -- the stock flare's), the black horizon 1.0
                     portal = { enabled = true, diameter_m = 120, min_deg = 1.5, lead_s = 3.0, open_s = 1.2, hold_s = 5.0, close_s = 1.0,
                                lens_size = 2.4, lens_x = 3, glow_size = 2.0, glow_x = 4, ring_size = 1.3, ring_x = 8,
                                textures = "/Game/Mods/SurvivalMode/Valka/Portal/" },
                     flare = { enabled = true, life_s = 7, intensity_x = 6,
                               path = "/Game/Mods/SurvivalMode/Valka/Flare/MI_SV_ValkaFlare_",
                               elements = { { "Glare", 1.6 }, { "Ring", 1.2 }, { "Shine", 0.9 }, { "Bokeh", 0.4 } },
                               curve = { { 0, 1 }, { 0.1, 1 }, { 0.831, 0.84 }, { 1, 0 } } },
                     -- her railgun's round (both her railguns: hers and the opener's): the land battleship's (user,
                     -- 2026-10-24: "try putting a land battleship railgun weapon on her EML"; "" = the x40a's own)
                     eml_weapon = "/Game/Blueprints/Weapons/EML/Ldbs/BP_wp_eml_ldbs01",
                     -- its rounds live at least eml_life_s (so the opener's reaches past you; user, 2026-10-24: "edit the
                     -- range on the land battleship railgun round so it does reach past me"), on Survival's rounds only
                     -- (the land battleship's class default stays stock). The opener's shot is aimed at a dummy
                     -- opener_miss_up_m above you and its rounds do no damage (user: "that first shot HAS to miss me").
                     -- (tools/survival_events.py VALKA_MISS_UP_M: keep in step)
                     eml_life_s = 30, opener_miss_up_m = 250,
                     -- her railguns on the minimap (user, 2026-10-24: "add a minimap beam as to where the railgun is being
                     -- fired from"): their launchers' radar display on, forced, in radar_hud's style
                     -- (ELiveFCSRailGunHUDControl: 0 RailGun, 1 LongRangeRailGun, 2 DiffusionRailGun), and the railgun
                     -- alert on while she's up (Mission 18's LiveSetRailgunAlertEnable)
                     radar_hud = 1, alert_off_s = 3,
                     -- where her railgun sits on the X-02S (cm in her frame: forward, right, up): under her nose
                     railgun_at = { X = 400, Y = 0, Z = -80 },
                     -- railgun_show: a part shown there (a Lua pattern in its actor name), railgun_scale big; "" = none (the
                     -- user, 2026-10-24: her railgun is AC7's EML housing, SWP3, built into her X-02S, not an x40a part)
                     railgun_show = "", railgun_scale = 0.5,
                     camera = "LookAt_Event_Camera_ms22-01",
                     -- she comes after you more (user, 2026-10-24: "adjust her behaviours so that she tries to follow you
                     -- more often"): LastTGT every turn_every_s and at once when you're behind her within behind_km, and her
                     -- orders (search and attack: you only) given again every engage_every_s
                     turn_every_s = 6, behind_km = 3, behind_gap_s = 2.5, engage_every_s = 5,
                     post_stall = true, post_stall_every_s = 9, post_stall_range_km = 3,
                     post_stall_moves = { "Kulbit", "KulbitB", "Cobra" },
                     blink_s = 4, blink_every_s = 1.0, blink_turn_deg = 60, ground_clear_m = 150, blink_cooldown_s = 8,
                     smoke = "/Game/VFX/Vehicles/Aircraft/Common/Bailout/NS_BailoutSmoke001", smoke_scale = 4.0,
                     smoke_s = 3.0,
                     railgun_every_s = 15, railgun_charge_s = 2.5, railgun_range_km = 5, railgun_cone_deg = 25,
                     single_shot = 1,
                     -- weapons added to her row's empty slots (slot = fire-control row): the x40a row carries flares and
                     -- missiles only; both on MINDRIPPER's quick fire control
                     weapons = { [1] = "NPC_FCS_PlaneGun000", [3] = "NPC_FCS_PlaneQAAM000" },
                     invert = "random", invert_every_s = 20, invert_chance = 0.35, invert_s = 8, fade_s = 1.0,
                     random_fx = { "pitch", "roll", "yaw", "swap", "throttle" }, random_min = 1, random_max = 2,
                     -- her teleport rings (tools/survival_events.py VALKA_SPOTS; keep in step, not an ini setting):
                     -- { ring, metres, step deg }: her blinks
                     spots = { { "B", 500, 30 }, { "C", 800, 30 } } },
        -- "ladon" = two Ladons, KOT and MISHKA (tools/survival_events.py LADON*; user, 2026-10-23): from the far west
        -- along a long route and over the airfield, then round it again and again, bombing it (bomb_damage) on every
        -- pass, until both are down. Nothing else flies in their round. Their rows: health_add HP on the Ladon's
        -- 1200, speeds x speed_x (1.0 since the route's speed went to 2500 km/h, user 2026-10-23: their rows mustn't cap
        -- it; the route's own speed is built in: LADON_SPEED). Each one down pays `reward` (+ reward_per_round x the round).
        -- volley_*: its missiles (RE_SV_LadonVolley<Key>L / R: the hatch opens, one launcher fires its salvo at you,
        -- left and right in turn) every volley_every_s while you're within volley_range_km of it, the first once
        -- you've been in range volley_warn_s, and never within volley_gap_s of the other Ladon's; its pulse cannons
        -- fire on their own. (Was both launchers every 20 s within 12 km: the player was down within 9 s of the first
        -- volley, test of 2026-10-23; then both Ladons fired together, a friend's test the same day.)
        -- missile_*: their VLS missiles (BP_wp_vls_ladon: 15 damage, 60 deg homing cone) as they appear in Survival:
        -- damage missile_damage (user, 2026-10-29: "make the missile damage they have at 10"; was x0.8, 12), homing cone
        -- x missile_homing_x (user, 2026-10-24: "tone that down too, only minorly"), turn rate (MaxRotationAngle and
        -- its not-captured one) x missile_turn_x (user, 2026-10-29: "make their missiles turn less faster, they're
        -- almost unavoidable").
        -- Their own fire control's sure kill (BP_wp_vls_certain_ladon) is made one of those (a run of 2026-10-24:
        -- "Ladons shooting down players with one missile").
        -- Health: user, 2026-10-24 "lower their health dramatically": 400 HP (was 900), x1.21 by round 12 (was x1.32).
        -- (health_per_round 0.05, health_max_x 2.5: were 0.03 / 2.0, economy review of 2026-10-25)
        -- rage (behaviour roadmap P7: "after one Ladon dies the other changes route and volleys faster"; their round
        -- stays theirs alone, user 2026-10-25, so no escorts; tools/re/BEHAVIOUR_DIRECTOR.md unit 9): one shot down, the
        -- other is enraged: its volleys every rage.volley_every_s (the first first_s on, rage.volley_warn_s in range),
        -- and from its next pass over the airfield it flies a tighter circuit at the build's faster speed
        -- (tools/survival_events.py LADON_RAGE: RE_SV_LadonRage<Key> sets its flag, the PathFinish records pick the
        -- path). false: as before
        ladon = { names = { Kot = "KOT", Mishka = "MISHKA" }, health_add = -800, speed_x = 1.0, bomb_damage = 20,
                  bomb_per_round = 1, health_per_round = 0.05, health_max_x = 2.5,
                  rage = { enabled = true, volley_every_s = 25, volley_warn_s = 0, first_s = 5 },
                  volley_every_s = 45, volley_range_km = 8, volley_warn_s = 10, volley_gap_s = 22,
                  missile_damage = 10, missile_homing_x = 0.85, missile_turn_x = 0.5,
                  reward = 6000, reward_per_round = 200,
                  npc_rows = "/Game/Mods/SurvivalMode/Data/DT_SV_NpcRows.DT_SV_NpcRows" },
        -- "amphibious" = Amphibious Assault (SURVIVAL_SPEC.md 7; tools/survival_events.py LCAC_*): landing craft on
        -- `lanes` (from the user's marks; `craft` craft each, side by side) cross to Comona's beaches by the airport,
        -- lanes_first of them the first time, lanes_more more each time after; each craft that reaches the beach puts a
        -- BTR-90 ashore, which drives to the runway. Each one that gets there adds capture_per_troop % to the airfield's
        -- capture (on the HUD); at 100 it is captured (landing and the STORE closed, "AIRFIELD CAPTURED") for
        -- captured_rounds rounds, or until every landed troop vehicle is destroyed (user, 2026-10-23: "each troop that
        -- reaches the runway should put a percentage on the HUD ... when it reaches 100% the airfield is captured").
        -- A round that ends short of 100 starts the next landing from 0. The round's
        -- fighters come as in a normal round, and bomber_chance of the time a bomber raid on the airfield with them
        -- (user: "enemy aircraft still spawn also, with a chance for bombers to also spawn"). No capture: `reward`
        -- (+ reward_per_round x the round); each craft pays craft_pay, each troop vehicle troop_pay (times the tier's
        -- pay, as aircraft). Craft that landed are taken off remove_after_s after landing (they're heading out).
        -- (user, 2026-10-23: "spawn all LCAC lanes, make it difficult": every lane every time, 16 craft, extra_aircraft
        -- more fighters than the round's own and a bomber raid more often)
        amphibious = { lanes = { "A", "B", "C", "D" }, craft = { "W", "X", "Y", "Z" }, lanes_first = 4, lanes_more = 1,
                       capture_per_troop = 25, extra_aircraft = 4,
                       captured_rounds = 2, bomber_chance = 0.6, reward = 4000, reward_per_round = 160,
                       craft_pay = 150, troop_pay = 150, remove_after_s = 90,
                       -- troop vehicles that stop short of the runway (a friend's test of 2026-10-23: 5 troops ashore,
                       -- none moving or to be found, so the round never ended): one that hasn't moved stuck_m in
                       -- stuck_s is taken off (no pay, no capture); without its actor to watch, after troop_timeout_s.
                       -- runway_cm: where they drive to (survival_events.LCAC_RUNWAY), for the log's distances.
                       stuck_m = 50, stuck_s = 60, troop_timeout_s = 540, runway_cm = { 1609574, -435747 } },
        -- reward_per_round: added to `reward` x the round (2026-10-23: a late special paid less than a normal round)
        shuttle  = { name = "EMBDIR Shuttle - CORRIS", countdown_s = 150, reward = 6000, reward_per_round = 200, strike_share = 0.4,
                     -- pad_allies: Mission 22's pad guns, SAMs and tower around the shuttle during the countdown
                     -- (removed after it, tools/survival_events.py PAD_REMOVE_LOST_S / SHUTTLE_REMOVE_S)
                     -- remove_s: liftoff to the shuttle and pad being taken off; = SHUTTLE_REMOVE_S (its flags reset after it)
                     remove_s = 180,
                     pad_allies = true, dummies = "SV_Unit_PadDummies",
                     shop_closed_rounds = 1, unit = "SV_Unit_Shuttle", pad = "AA_Unit_01_Ground0",
                     name_key = "SV_Shuttle_Name", npc_row = "OP0057_sstb_01_SV",
                     npc_rows = "/Game/Mods/SurvivalMode/Data/DT_SV_NpcRows.DT_SV_NpcRows" },
        -- "anomaly" = The Anomaly (tools/survival_events.py ANOMALY_*; user, 2026-10-22): the ace `name` in an F-4E
        -- (the campaign named-ace skin) with `guards` escorts under `guards_name`, both at the top skill tier and AI
        -- level ai_level. Within field_km of it the player's controls invert (`invert`: "both", "pitch" or "roll",
        -- or "random": each time you come into it, random_min..random_max of random_fx: pitch / roll / yaw (rudder)
        -- inverted, swap (pitch and roll swapped), throttle (throttle and brake swapped); user, 2026-10-24),
        -- fading over fade_s (dlls/main.dll SV_Invert), with the stock glasses effect and radar noise; its
        -- round starts with the stock MISSION UPDATE beep, a forced WARNING and the focus camera on it. Shot down:
        -- `reward` zollars, controls back. The round ends when it and every other enemy are down.
        -- field_km 3.2: the ECM pod's ring on the radar is 3.2 km (BP_wp_ecm_a0), so the ring shows the field
        anomaly  = { name = "MINDRIPPER", guards_name = "PHANTASM", guards = 4, field_km = 3.2, invert = "random",
                     random_fx = { "pitch", "roll", "yaw", "swap", "throttle" }, random_min = 1, random_max = 2,
                     fade_s = 1.5, reward = 8000, reward_per_round = 300, ai_level = 5, guard_offset_m = 800,
                     -- its health for its round (economy review of 2026-10-25): x (1 + health_per_round a round after
                     -- specials.first), at most health_max_x, set when it appears
                     health_per_round = 0.05, health_max_x = 2.5,
                     -- its round has nothing else in it (user, 2026-10-22: "no other aircraft other than those special
                     -- to those levels should spawn")
                     only = true,
                     -- stronger (user: "make the F-4 more stronger"; 1000 HP from 2026-10-24, was 500: a friend's
                     -- test had it down to 2 missiles 12 s into its field): the F-4E has 60 HP and turns slowly (pitch 30,
                     -- roll 90); its DT_NPC rows get health_add HP and turn_add degrees/s (MaxHealthDifference,
                     -- Pitch/Roll/YawSpeedDifference). hover: it floats (user: "didn't hover in place"): its speeds
                     -- times hover_speed (Speed*Coefficient), so it hangs in the air and turns on the spot.
                     health_add = 940, turn_add = { pitch = 120, roll = 270, yaw = 25 }, hover = true, hover_speed = 0.06,
                     -- (user, 2026-10-22: "make MINDRIPPER 5x more aggressive with everything"): its own fire control
                     -- from the top difficulty spike's, `aggression` times quicker (arm, lock, time on target, between
                     -- shots, rests; gun bursts that many times longer), half again the reach and cone, gun rounds x2
                     -- damage at half the spread; every special weapon it has room for; it reacts to you `aggression`
                     -- times quicker (provoke) and sits closer on your tail (surround_m).
                     aggression = 5, provoke_cone_deg = 30, surround_m = { 20, 60 },
                     -- its gun on top of that (user, 2026-10-24: "increase its gun accuracy and distance 20x"): spread
                     -- / gun_accuracy_x, firing range and its rounds' life (how far they fly) x gun_reach_x
                     gun_accuracy_x = 20, gun_reach_x = 20,
                     -- and it leads you (user, 2026-10-24: "make MINDRIPPER lead targets with its gun"): it aims where
                     -- you'll be gun_lead_s ahead (PredictionOffsetTime; its rounds fly 833 m/s, so 1 s suits ~0.8 km)
                     gun_lead_s = 1.0,
                     -- its guards' search range: they see you only this close, so they stay circling it and jump you
                     -- when you come near (test of 2026-10-22: with the 40 km search they left it for you and the airfield)
                     guard_search_m = 5000,
                     -- its pack (behaviour roadmap P7: "PHANTASM guards fly as a Wolf pack that springs while your controls
                     -- are scrambled"; tools/re/BEHAVIOUR_DIRECTOR.md unit 9): spring_delay_s after its field scrambles
                     -- you, its tell first ("pack"), the guards are let loose (RE_SV_AnomalyPackSpring: you only, anywhere,
                     -- and every one of them the campaign aces' LastTGT onto you); once you've been out of the field
                     -- hold_after_s, and at least min_s after the spring, they're called back round it
                     -- (RE_SV_AnomalyPackHold, their appearance's orders), cooldown_s before the next. The host's field
                     -- only (LastTGT steers to the host; a co-op joiner's own field doesn't spring it). guard_luaset: the
                     -- behaviour set the guards fly (the Wolf trap's close gunfighter, CFG.behaviour_sets; set at the main
                     -- menu: a game restart to change; "" the fighters'). hunt_only_sprung: their target kept on you
                     -- (the top tier's hunt) only while sprung. false: no pack (the guards as before)
                     pack = { enabled = true, spring_delay_s = 1.5, min_s = 12, hold_after_s = 4, cooldown_s = 20,
                              hunt_only_sprung = false, guard_luaset = "NLID_SV_WolfWing" },
                     -- its weapon slots after the gun and missiles: two special weapons and the E-18G ace's ECM pod
                     -- (user, 2026-10-22: "a warning to the minimap for MINDRIPPER, similar to what the ECM uses": the
                     -- game draws an ECM carrier's area on the radar itself; it also makes your missiles miss near it)
                     weapons = { "NPC_FCS_PlaneQAAM000", "NPC_FCS_Plane2AAM000", "NPC_FCS_ECM000" },
                     -- its arrival camera (tools/survival_events.py ANOMALY_CAMERAS; the shuttle's ms22-01 was too close)
                     -- (the shuttle's ms22-01 was too close at ~20 km: the game zooms in harder the farther the target
                     -- is; the Celaeno's ms23-01 at 8-12 km was too far out: user, 2026-10-22, "go back to the
                     -- shuttle's") the shuttle's camera, with the portal spawn_km from you, any direction (nil: anywhere)
                     -- (spawn_km 8-12 put back to the ~20 km out it was: user, 2026-10-22, "put it back to 20km")
                     camera = "LookAt_Event_Camera_ms22-01", spawn_km = { 0, 0 },     -- (0, 0: off)
                     unit = "SV_Unit_Anomaly", guard_unit = "SV_Unit_AnomalyGuards",
                     -- the Celaeno's death sounds (Mission 23's sound events, played by the event package when it's
                     -- down: tools/survival_events.py ANOMALY_DOWN_SOUNDS), loaded with the level so they can play
                     down_sounds = "/Game/WwiseAssets/Events/CS_AceLive_SE/MissionSpecific/Events_Ms23/EXP/SKY/SE_Ms23_EXP_SKY_OP0049_cleo/",
                     down_sound_names = { "AKE_Ms23_EXP_SKY_OP0049_cleo_Body_Killed_seq01_Play",
                                          "AKE_Ms23_EXP_SKY_OP0049_cleo_Body_Killed_seq02_Play",
                                          "AKE_Ms23_EXP_SKY_OP0049_cleo_Body_Killed_seq03_Play" },
                     -- (and the Celaeno's control-unit crackle on MINDRIPPER while it's up)
                     hum_sounds = "/Game/WwiseAssets/Events/CS_AceLive_SE/MissionSpecific/Events_Ms23/ARMS/SKY/SE_Ms23_ARMS_SKY_OP0049_cleo/",
                     hum_sound_names = { "AKE_Ms23_ARMS_SKY_OP0049_cleo_ControlUnit_Electricity_Play",
                                         "AKE_Ms23_ARMS_SKY_OP0049_cleo_ControlUnit_Electricity_Stop",
                                         "AKE_Ms23_ARMS_SKY_OP0049_cleo_ControlUnit_Collapse_Play" },
                     -- The portal (user, 2026-10-22: "the zoom in camera appears, then the portal, then MINDRIPPER";
                     -- lightning from the game's own electric effects). MINDRIPPER and its guards spawn hidden, the
                     -- event package's focus camera swings onto MINDRIPPER, open_at_s later the `open` systems crackle
                     -- on it for open_s, then the `burst` systems fire and they appear. Niagara systems, attached to
                     -- MINDRIPPER, `scale` times their size (they're made for one aircraft).
                     -- (user: "effects could be better"): lightning strikes all round it while it opens (strike, one
                     -- every strike_every_s within strike_m), the burst with more of them, a crackle on MINDRIPPER every
                     -- aura_every_s while it's up, and the burst again where it's shot down.
                     portal = { enabled = true, open_at_s = 1.0, open_s = 3.0, scale = 6.0,
                                strike = "/Game/VFX/Environment/Common/Lightning/CloudLightning/NS_CloudLightning",
                                strike_every_s = 0.3, strike_m = 350, burst_strikes = 8,
                                aura = "/Game/VFX/Vehicles/Aircraft/Common/ElectricDischarge/NS_ElectricSign001",
                                aura_every_s = 2.0, aura_scale = 3.0,
                                -- every system it spawns is switched off fx_life_s after it starts (the burst where it
                                -- falls: death_fx_s), and all of them at once when it's shot down (user, 2026-10-23:
                                -- "make sure that the electric discharge despawns after the kill")
                                fx_life_s = 3.0, death_fx_s = 4.0,
                                open = { "/Game/VFX/Vehicles/Aircraft/Common/ElectricDischarge/NS_ElectricSign001",
                                         "/Game/VFX/Environment/Common/Lightning/CloudLightning/NS_CloudLightning" },
                                burst = { "/Game/VFX/Vehicles/Aircraft/Common/ElectricDischarge/NS_ElectricDischargeM001",
                                          "/Game/VFX/Mission/Mission023/NS_ms23FarFlash",
                                          "/Game/VFX/Mission/Mission027/CoreDestroy/NS_MGF_CoreDest1st_CoreElectricPlasma" } } },
    },
    -- Music (dlls/main.dll 0.9.0 SV_PlayBGM: the game's own BGM controller, which fades the old track out). Round 1
    -- keeps the mission-start track (start_track, posted by the event package); from round 2 each round starts the next
    -- track of a shuffled list, every 5th round one from `special`. A track is posted again when nothing has played
    -- for restart_s (user, 2026-10-21: the music stopped around round 5). All are looping campaign tracks of the BGM
    -- bank Survival's level loads (tools/re/MUSIC_RADIO_CAMERA.md); a name the game doesn't have is dropped.
    -- pause_player: free flight's Music Player row in Survival's pause menu; once the player opens it, Survival stops
    -- changing the music for the rest of the run.
    -- enabled = false (user, 2026-10-22): no round music at all, the Music Player is the only music (the mission-start
    -- track played over it; tools/survival_events.py MUSIC is None too). true brings the round rotation back.
    -- hold_clock: the Music Player ends each track by its own clock, which ran on through pauses, so every pause cut the
    -- track short (user, 2026-10-22: "music skipped on round change"); dlls/main.dll 0.12.0 holds it while the BGM is
    -- paused (SV_MusicClock, tools/re/MUSIC_RADIO_CAMERA.md "Track skips in Survival").
    music = {
        enabled      = false,
        pause_player = true,
        hold_clock   = true,
        start_track  = "AKE_Bgm_Ms08A_Play",
        restart_s    = 15,
        tracks  = { "AKE_Bgm_Ms02A_Play", "AKE_Bgm_Ms04A_Play", "AKE_Bgm_Ms05a_Play", "AKE_Bgm_Ms07A_Play",
                    "AKE_Bgm_Ms11A_Play", "AKE_Bgm_Ms12a_Play", "AKE_Bgm_Ms14A_Play", "AKE_Bgm_Ms17A_Play",
                    "AKE_Bgm_Ms18A_Play", "AKE_Bgm_Ms20A_Play", "AKE_Bgm_Ms21A_Play", "AKE_Bgm_Ms22A_Play",
                    "AKE_Bgm_Ms24A_Play" },
        special = { "AKE_Bgm_Ms09B_Play", "AKE_Bgm_Ms20D_Play", "AKE_Bgm_Ms23B_Play", "AKE_Bgm_Ms27A_Play",
                    "AKE_Bgm_Ms28C_Play", "AKE_Bgm_Ms30A_Play" },
    },
    -- Round HUD. Positions are on the game's HUD design canvas (3840x2160, scaled to the screen; tools/re/HUD_LAYOUT.md).
    hud = {
        enabled          = true,
        x                = 190,                 -- left edge, lined up with the game's TIME / SCORE stack
        -- Below the game's stack: TIME 108, SCORE 176 (test 13 screenshot) and the TARGET row at 244, which appears
        -- when the player locks on and covered ROUND at 244 (user screenshot, 2026-10-22).
        y                = 312,
        hide_game_timer  = true,                -- hide the stack's TIME row (Survival's mission clock is paused)
        hide_score_limit = true,                -- SCORE shows the score alone, without the mission's "/32000"
        -- AIRFIELD row (under ROUND): health bar after the label (offsets from the row's left / top), then its number
        airfield_bar     = { x = 270, dy = 15, w = 300, h = 24, frame = 3 },
        warn_color       = { 1.0, 0.3, 0.2 },   -- the bar at or under warn_hp
        warn_hp          = 25,
        line             = 68,                  -- row pitch of the game's stack
        font_size        = 37,                  -- the mission info panel's text: HUD typeface 37, spacing -70
        letter_spacing   = -70,
        banner_letter_spacing = -35,
        -- The game draws its HUD white and tints it in a post-process (green by default, plus a glow); ours is a
        -- plain widget, so it gets the measured green (linear RGB) and a faint outline in place of the glow.
        color            = { 0.26, 1.0, 0.33 },
        -- the end-of-run summary's panel (user, 2026-10-23: "a dark green background with light green edges so that we
        -- can see the text better"): its box on the 3840 x 2160 layout, its fill (r, g, b, a) and edge colour / width
        summary          = { w = 1700, y = 520, h = 690, fill = { 0.02, 0.16, 0.05, 0.82 }, edge = { 0.6, 1.0, 0.65 }, edge_px = 4 },
        opacity          = 0.9,
        glow_size        = 2,                   -- outline width; 0 = none
        glow_alpha       = 0.25,
        banner_y         = 894,                 -- centre of the callout banner (the game's MessageLayerOne)
        banner_char_w    = 32,                  -- estimated width of a banner letter (design units)
        banner_pad       = 70,                  -- space between the banner's text and its box, each side
        callout_s        = 4,                   -- how long a callout stays up
        start_callout_lead_s = 3,               -- "ROUND n" this long before the round's first flight
        zorder           = 0,
        -- The info key (user, 2026-10-29: "assign a hotkey like 'i' for information ... details that don't need to be
        -- seen constantly are hidden unless the player wants to see them"; 2026-10-31: "an information wall that appears
        -- in the center of the screen on a button press and hides on a button press ... similar to how the end of round
        -- information screen works", the corner had room for 4 players): the CO-OP, ALLIES and ITEMS rows under NEXT
        -- ROUND stay hidden, each shown peek_s when its news changes (a player joins, drops or is shot down; an ally
        -- flight, ship or defence comes or goes, or the allies' order changes; an item bought or used); `key` (a UE4SS
        -- Key name: a letter, F5, ...; with Ctrl when ctrl) opens the info wall (`wall`) in the screen's middle and
        -- shuts it, the corner's rows hidden while it's open. Only in a run (a press elsewhere does nothing); start_open:
        -- open as each level starts. Keyboard only: a UE4SS key bind (a pad button would need the runtime's input hook),
        -- and the game gets the key too. enabled = false: those rows always shown, no wall. Each player's own (co-op never
        -- syncs hud).
        info             = { enabled = true, key = "I", ctrl = false, start_open = false, peek_s = 5.0 },
        -- the info wall: a panel like the run's summary (its fill and edge), centred on y_mid, as tall as it needs; w
        -- wide, or w2 with the players in two columns (cols_from players or more, each column col_dx off the middle);
        -- the title title_dy under its top, the first row `top` under it, the footer `bottom` above its foot
        wall             = { y_mid = 1000, w = 2200, w2 = 3000, col_dx = 740, cols_from = 9, top = 130, bottom = 100,
                             title_dy = 40 },
        text = {
            round        = "ROUND: %d",
            next_round   = "NEXT ROUND: %s",
            first_round  = "ROUND 1 IN: %s",
            complete     = "ROUND %d COMPLETE",
            complete_sub = "NEXT ROUND IN %d SECONDS",
            credits      = "ZOLLARS: %d",
            airfield     = "AIRFIELD:",
            airfield_down_row = "AIRFIELD: DOWN",
            bombers      = "BOMBERS INBOUND",
            bombers_sub  = "PROTECT THE AIRFIELD",
            under_attack = "AIRFIELD UNDER ATTACK",
            airfield_down     = "AIRFIELD DOWN",
            airfield_down_sub = "NO LANDING UNTIL AFTER ROUND %d",
            airfield_up       = "AIRFIELD REPAIRED",
            airfield_up_sub   = "CLEARED TO LAND",
            start        = "ROUND %d",
            start_sub    = "HOSTILES INBOUND",
            special      = "SPECIAL ROUND %d",
            shuttle_sub  = "DEFEND THE %s",
            launch_row   = "LAUNCH IN: %s  SHUTTLE %d%%",
            launched     = "SHUTTLE LAUNCHED",
            launched_sub = "+%d ZOLLARS",
            shuttle_lost = "SHUTTLE LOST",
            shuttle_lost_sub = "SHOP CLOSED NEXT ROUND",
            shop_closed  = "SHOP CLOSED: THE SHUTTLE WAS LOST.",
            spike        = "DIFFICULTY UP",
            spike_sub    = "ENEMY PILOTS GROW SHARPER",
            ace          = "ACE INBOUND: %s",
            anomaly_sub  = "ANOMALY DETECTED",
            glitch_sub   = "IFF: FATAL ERROR",
            glitch_row   = "%s: %.1f KM",
            glitch_row_frenzy = "%s: SIGNAL UNSTABLE",
            glitch_row_allout = "%s: ECM DOWN  %.1f KM",  -- (its phase 3: CFG.specials.glitch.phases)
            valka_sub    = "ELECTROMAGNETIC LAUNCHER DETECTED",
            valka_charge = "WARNING: RAILGUN",
            valka_charge_sub = "EML CHARGING",
            valka_row    = "%s: %.1f KM",
            valka_row_charge = "%s: RAILGUN CHARGING",
            valka_row_field  = "%s: %s",                 -- (her name, the scramble: anomaly_fx joined by " + ")
            anomaly_warn = "WARNING: %s",
            anomaly_warn_sub = "ITS FIELD SCRAMBLES YOUR CONTROLS",
            anomaly_field     = "ANOMALY FIELD",
            anomaly_field_sub = "%s",                     -- (what the field does this time: anomaly_fx joined by " + ")
            anomaly_clear     = "CONTROLS RESTORED",
            anomaly_row       = "%s: %.1f KM",
            anomaly_row_field = "ANOMALY FIELD: %s",
            anomaly_fx        = { pitch = "PITCH INVERTED", roll = "ROLL INVERTED", yaw = "RUDDER INVERTED",
                                  swap = "STICK AXES SWAPPED", throttle = "THROTTLE / BRAKE SWAPPED" },
            anomaly_down      = "%s DOWN",
            anomaly_down_sub  = "+%d ZOLLARS",
            aces_round   = "ACE SQUADRONS: %s",
            ladon_sub    = "LADONS INBOUND",
            lb_title     = "RUN OVER: %s",
            lb_lines     = { "ROUND REACHED  %d", "SCORE  %s", "KILLS  %d AIR, %d GROUND", "SPECIALS BEATEN  %d",
                             "TIME  %s", "ZOLLARS EARNED  %s", "BY ALLIES  %d, BY DEFENCES  %d" },
            -- (economy review of 2026-10-25: waves, raids, the jammer, ally kills, tactical items)
            round_wave   = "ROUND: %d   WAVE %d/%d",
            wave_in      = "WAVE %d OF %d",
            wave_in_sub  = "%d AIRCRAFT INBOUND",
            raid         = "BOMBER RAID FROM THE %s",
            raid_sub     = "%d BOMBERS: PROTECT THE AIRFIELD",
            raid_row     = "RAID: %d BOMBERS FROM THE %s",
            strike_air   = "STRIKE FLIGHT INBOUND",
            strike_air_sub = "HEADING FOR THE AIRFIELD",
            jammer       = "ENEMY JAMMER INBOUND",
            jammer_sub   = "THE EA-18G SHARPENS EVERY PILOT NEAR IT",
            jammer_down  = "JAMMER DOWN",
            jammer_down_sub = "+%d ZOLLARS",
            allies_row   = "ALLIES: %s",
            items_row    = "ITEMS: %s",
            -- the info wall (CFG.hud.wall): its title, rows and footer (the key's name in it)
            wall_title   = "INFORMATION",
            wall_allies  = "ALLIES:  %s",
            wall_items   = "ITEMS:  %s",
            wall_none    = "NONE",
            wall_kills   = "THIS RUN'S KILLS:  YOU %d   ALLIES %d   SHIPS %d   DEFENCES %d",
            wall_close   = "PRESS %s TO CLOSE",
            kills        = "ROUND %d KILLS",
            kills_sub    = "YOU %d   ALLIES %d   SHIPS %d   DEFENCES %d",
            airstrike    = "AIRSTRIKE INBOUND",
            airstrike_sub = "TARGET: %d AIRCRAFT",
            airstrike_none = "AIRSTRIKE HELD",
            airstrike_none_sub = "NO ENEMY FLIGHT WITHIN %d KM",
            airstrike_hit = "AIRSTRIKE: %d DOWN",
            ecm          = "ECM BURST",
            ecm_sub      = "ENEMY LOCKS BROKEN FOR %d SECONDS",
            decoy        = "DECOY RELEASED",
            decoy_sub    = "%d AIRCRAFT BREAK OFF",
            decoy_none   = "DECOY HELD",
            decoy_none_sub = "NO ENEMY FLIGHT WITHIN %d KM",
            insured      = "SECOND CHANCE",
            insured_sub  = "AIRCRAFT RESTORED: DON'T WASTE IT",
            lb_sending   = "SENDING...",
            lb_sent      = "SUBMITTED: SCORE %s",
            lb_queued    = "NO CONNECTION: IT WILL BE SENT NEXT TIME",
            lb_refused   = "NOT ACCEPTED: %s",
            lb_unranked  = "NOT RANKED: %s",              -- (an edited run: LB.edited, sv_leaderboard.lua)

            alicorn_sub  = "SUBMARINE CONTACT",
            alicorn_go   = "THE ALICORN",
            alicorn_go_sub = "DESTROY ITS BALLAST TANKS, THEN ITS CORE",
            alicorn_row  = "ALICORN: BALLAST TANKS %d/4  CORE %s%s",
            alicorn_dive = "THE ALICORN IS DIVING",
            alicorn_surface = "THE ALICORN HAS SURFACED",
            alicorn_core = "CORE EXPOSED",
            alicorn_core_sub = "HIT THE ALICORN'S CORE",
            alicorn_down = "THE ALICORN IS SINKING",
            alicorn_down_sub = "+%d ZOLLARS",
            ladon_go     = "LADONS FROM THE WEST",
            ladon_go_sub = "STOP %s AND %s BEFORE THEY REACH THE AIRFIELD",
            ladon_row    = "LADONS LEFT: %d  BOMBING RUNS: %d",
            ladon_run    = "%s: BOMBING RUN",
            ladon_run_sub = "THE AIRFIELD IS HIT",
            ladon_down   = "%s DOWN",
            ladon_down_sub = "+%d ZOLLARS",
            amphib_sub   = "LANDING CRAFT INBOUND",
            amphib_go    = "AMPHIBIOUS ASSAULT",
            amphib_go_sub = "STOP THE LANDING CRAFT BEFORE THEY REACH THE BEACH",
            amphib_row   = "LANDING CRAFT: %d  TROOPS: %d  AIRFIELD CAPTURE: %d%%",
            ashore       = "TROOPS ASHORE",
            ashore_sub   = "STOP THEM BEFORE THEY REACH THE RUNWAY",
            troops_stuck = "TROOPS BOGGED DOWN",
            troops_stuck_sub = "%d OUT OF THE FIGHT",
            on_runway    = "TROOPS ON THE RUNWAY",
            on_runway_sub = "AIRFIELD %d%% CAPTURED",
            captured     = "AIRFIELD CAPTURED",
            captured_sub = "DESTROY THE LANDED TROOPS TO RETAKE IT",
            captured_row = "AIRFIELD CAPTURED: %d ROUND%s LEFT, %d TROOPS",
            retaken      = "AIRFIELD RETAKEN",
            retaken_sub  = "CLEARED TO LAND",
            freed        = "AIRFIELD BACK IN OUR HANDS",
            repelled     = "LANDING REPELLED",
            repelled_sub = "+%d ZOLLARS",
            shop_captured = "SHOP CLOSED: THE AIRFIELD IS CAPTURED.",
            ace_sub      = "%s SQUADRON (%s)",
        },
    },
}
for n = 1, 8 do for k = 0, 2 do CFG.pool[#CFG.pool + 1] = string.format("ERA_Unit_%02d_Dep_Air%d", n, k) end end
function deepCopy(v)
    if type(v) ~= "table" then return v end
    local t = {}
    for k, x in pairs(v) do t[k] = deepCopy(x) end
    return t
end
-- The shipped settings, before survival.ini and survival_config.lua change them: Survival COOP's host sends its
-- differences from these to every joiner (sv_coop.lua, M.sendSettings)
CFG_DEFAULTS = deepCopy(CFG)
-- The player's settings: config/survival.ini (BUILD_PLAN Milestone 4). Releases ship config/survival.default.ini; the
-- first run copies it to survival.ini, which an update never overwrites. A [section] names a CFG table (dots for
-- nested ones, any case; INI_ALIAS gives the friendly names), `key = value` sets a field that exists there: a number,
-- true / false, text, or a comma list for a list field. [squadrons] keys are squadron sizes (value: from_round).
-- Read once at start (the main menu builds Survival's NPC rows from CFG), so changes need a game restart.
do                                 -- (its helpers stay inside: the main chunk's 200-local limit)
local INI_ALIAS = { rounds = "", zollars = "credits", bombers = "airfield.bombers", skill = "tiers",
                    ["skill.difficulty"] = "tiers.rank_add", enemy_missiles = "missiles", enemy_guns = "guns",
                    ["ammo.casual"] = "ammo.presets.casual", ["ammo.standard"] = "ammo.presets.standard",
                    ["ammo.ace"] = "ammo.presets.ace",
                    -- (0.35.3's name for the aircraft repair, still in the survival.ini files it extended)
                    ["shop.airfield.aircraft"] = "shop.items.RepairAircraft" }
-- sections of things since taken out, still in older survival.ini files: skipped without a warning
local INI_RETIRED = { ["shop.shipfreedom"] = true, ["allies.ships.freedom"] = true }
local function iniSection(name)
    local path = name:lower()
    path = INI_ALIAS[path] or path:gsub("^shop%.", "shop.items.")
    local t = CFG
    for part in path:gmatch("[^%.]+") do
        local found = nil
        for k, v in pairs(t) do if type(k) == "string" and k:lower() == part:lower() and type(v) == "table" then found = v end end
        if not found then return nil end
        t = found
    end
    return t
end
local function iniValue(old, s)
    if type(old) == "boolean" then
        local b = ({ ["true"] = true, yes = true, on = true, ["1"] = true, ["false"] = false, no = false, off = false, ["0"] = false })[s:lower()]
        return b, b ~= nil
    elseif type(old) == "number" then
        local n = tonumber(s)
        if n and math.type(old) == "integer" then n = math.tointeger(n) or math.floor(n + 0.5) end
        return n, n ~= nil
    elseif type(old) == "string" then
        return s, true
    elseif type(old) == "table" and #old > 0 and type(old[1]) ~= "table" then
        local list = {}
        for item in s:gmatch("[^,]+") do
            item = item:match("^%s*(.-)%s*$")
            if type(old[1]) == "number" then item = tonumber(item); if not item then return nil, false end end
            list[#list + 1] = item
        end
        return list, #list > 0
    end
    return nil, false
end
-- Settings an update added to survival.default.ini (a key or a section survival.ini doesn't have, switched on or off)
-- are appended to survival.ini, switched off, with the comment lines above them, so players find them there (user,
-- 2026-10-22: "I couldn't find it in the ini"). Nothing the player wrote is changed.
local function mergeDefaults(dir)
    local d = io.open(dir .. "survival.default.ini", "r")
    local u = io.open(dir .. "survival.ini", "r")
    if not (d and u) then if d then d:close() end; if u then u:close() end; return end
    local have, sec = {}, ""
    for line in u:lines() do
        local h = line:match("^%s*%[%s*(.-)%s*%]")
        if h then sec = h:lower()
        else
            local k = line:match("^%s*;?%s*([%w_]+)%s*=")
            if k then have[sec .. "/" .. k:lower()] = true end
        end
    end
    u:close()
    local out, comments, cur, curShown = {}, {}, "", false
    for line in d:lines() do
        local h = line:match("^%s*%[%s*(.-)%s*%]")
        local k = not h and line:match("^%s*;?%s*([%w_]+)%s*=")
        if h then
            cur, curShown, comments = h, false, {}
        elseif k then
            if cur ~= "" and not have[cur:lower() .. "/" .. k:lower()] then
                if not curShown then out[#out + 1] = ""; out[#out + 1] = "[" .. cur .. "]"; curShown = true end
                for _, c in ipairs(comments) do out[#out + 1] = c end
                out[#out + 1] = line:match("^%s*;") and line or (";" .. line)
            end
            comments = {}
        elseif line:match("^%s*;") then
            comments[#comments + 1] = line
        else
            comments = {}
        end
    end
    d:close()
    if #out == 0 then return end
    local w = io.open(dir .. "survival.ini", "a")
    if not w then return end
    w:write("\n; ---- settings added by Survival Mode " .. VERSION .. " (from survival.default.ini) ----\n")
    w:write(table.concat(out, "\n") .. "\n")
    w:close()
    log("config: added the new settings to survival.ini (" .. #out .. " lines)")
end

local function loadIni()
    local dir = SCRIPT_DIR .. "..\\config\\"
    pcall(mergeDefaults, dir)
    local f = io.open(dir .. "survival.ini", "r")
    if f then
        -- format 1 (Lua 0.24-0.25) copied every default as a live setting, which pinned them: a later default change never
        -- reached the player. Format 2 lists them switched off. An old file is kept as survival.ini.old.
        local text = f:read("a") or ""
        -- A file without the format line that sets only a few things was made by hand (a player who wrote just
        -- "[coop] role = join" before the game made one): it's kept and marked, not replaced (user, 2026-10-25:
        -- friends set role = join and still hosted). A format 1 file set every one of the ~300 settings.
        local live = 0
        for l in text:gmatch("[^\r\n]+") do if l:match("^%s*[%w_]+%s*=") then live = live + 1 end end
        if not text:find("survival.ini format 2", 1, true) and live < 60 then
            f:close(); f = nil
            local w = io.open(dir .. "survival.ini", "w")
            if w then
                w:write("; AC8 Survival Mode settings  (survival.ini format 2; this file was made by hand)\n" .. text)
                w:close()
                log("config: survival.ini has no format line and " .. live .. " settings (made by hand?): kept as it is")
            end
            f = io.open(dir .. "survival.ini", "r")
        elseif not text:find("survival.ini format 2", 1, true) then
            f:close(); f = nil
            os.remove(dir .. "survival.ini.old")
            local ok = os.rename(dir .. "survival.ini", dir .. "survival.ini.old")
            log("config: survival.ini is from an older version; " .. (ok and "kept as survival.ini.old, a new one is made"
                or "could not rename it, so it is used as it is"))
            if not ok then f = io.open(dir .. "survival.ini", "r") end
        else
            f:seek("set", 0)
        end
    end
    if not f then
        local d = io.open(dir .. "survival.default.ini", "r")
        if not d then return end
        local text = d:read("a"); d:close()
        local out = io.open(dir .. "survival.ini", "w")
        if out then out:write(text); out:close(); log("config: made config\\survival.ini from survival.default.ini") end
        f = io.open(dir .. "survival.ini", "r")
        if not f then return end
    end
    local t, section, set, bad, n = nil, nil, 0, {}, 0
    for line in f:lines() do
        n = n + 1
        line = line:gsub("^\239\187\191", ""):gsub("%s*[;#].*$", ""):match("^%s*(.-)%s*$")
        local sec = line:match("^%[%s*(.-)%s*%]$")
        if sec then
            section, t = sec, iniSection(sec)
            if not t and not INI_RETIRED[sec:lower()] then bad[#bad + 1] = string.format("line %d: no section [%s]", n, sec) end
        elseif line ~= "" then
            local key, val = line:match("^([^=]-)%s*=%s*(.*)$")
            if not key then
                bad[#bad + 1] = string.format("line %d: not 'key = value'", n)
            elseif t then
                local ok = false
                if t == CFG.squadrons then
                    for _, q in ipairs(t) do
                        if tostring(q.size) == key then local v = tonumber(val); if v then q.from_round, ok = v, true end end
                    end
                else
                    local field = nil
                    for k in pairs(t) do if type(k) == "string" and k:lower() == key:lower() then field = k end end
                    if field then
                        local v; v, ok = iniValue(t[field], val)
                        if ok then t[field] = v end
                    end
                end
                if ok then set = set + 1 else bad[#bad + 1] = string.format("line %d: [%s] %s = %s not used", n, section, key, val) end
            end
        end
    end
    f:close()
    log(string.format("config: survival.ini, %d settings%s", set, #bad > 0 and ("; " .. table.concat(bad, "; ")) or ""))
end
    local ok, err = pcall(loadIni)
    if not ok then log("config: survival.ini could not be read: " .. tostring(err)) end

-- A setting picked in game (the main menu's settings rows, sv_coop.lua) saved to survival.ini: its line in [section]
-- (switched off or not) becomes `key = value`, a later live line for it is switched off, and a missing one is added
-- under the section. Returns true when the file was written.
function iniSet(section, key, value)
    local path = SCRIPT_DIR .. "..\\config\\survival.ini"
    local lines, f = {}, io.open(path, "r")
    if f then for l in f:lines() do lines[#lines + 1] = l end; f:close() end
    local sec, at, secAt = nil, nil, nil
    for i, l in ipairs(lines) do
        local h = l:match("^%s*%[%s*(.-)%s*%]")
        if h then
            sec = h:lower()
            if sec == section:lower() and not secAt then secAt = i end
        elseif sec == section:lower() then
            local k = l:match("^%s*;?%s*([%w_]+)%s*=")
            if k and k:lower() == key:lower() then
                if not at then at = i elseif not l:match("^%s*;") then lines[i] = ";" .. l end
            end
        end
    end
    local line = key .. " = " .. tostring(value)
    if at then lines[at] = line
    elseif secAt then table.insert(lines, secAt + 1, line)
    else lines[#lines + 1] = ""; lines[#lines + 1] = "[" .. section .. "]"; lines[#lines + 1] = line end
    local w = io.open(path, "w")
    if not w then return false end
    w:write(table.concat(lines, "\n") .. "\n")
    w:close()
    return true
end
end
do  -- optional overrides: Scripts/survival_config.lua returning a table with any of the keys above. Lists (aircraft,
    -- pool, ...) are replaced whole; keyed tables (hud, hud.text) are merged, so one field can be changed alone.
    local function merge(into, from)
        for k, v in pairs(from) do
            if type(v) == "table" and type(into[k]) == "table" and #into[k] == 0 and next(into[k]) ~= nil then merge(into[k], v)
            else into[k] = v end
        end
    end
    local ok, user = pcall(require, "survival_config")
    -- (any survival_config.lua found, even one that failed or returned nothing, ran code of its own: the leaderboard
    -- doesn't rank a run with one, LB.edited in sv_leaderboard.lua)
    if ok or not tostring(user):find("module 'survival_config' not found", 1, true) then
        CFG_USER_FILE = "survival_config.lua"
        -- ONLINE ONLY BEGIN (tools/edition.py)
        log("config: a survival_config.lua is there: runs with it aren't ranked on the leaderboard")
        -- ONLINE ONLY END
    end
    if ok and type(user) == "table" then
        merge(CFG, user)
        log("config: survival_config.lua loaded")
    end
end
math.randomseed(os.time())

-- The difficulty preset (casual / standard / ace, CFG.ammo.by_difficulty) and the game's difficulty number.
presetCache = { at = -100 }
function presetName()
    local now = os.clock()
    if now - presetCache.at > 30 then           -- kept 30 s (Select Difficulty is hidden in Survival's pause menu)
        local dm = FindFirstOf("LiveDifficultyManager")
        local ok, d = pcall(function() return dm.CurrentDifficulty end)
        presetCache.at, presetCache.name, presetCache.d = now, (ok and CFG.ammo.by_difficulty[d]) or "standard", ok and d or nil
    end
    return presetCache.name, presetCache.d
end

---------------------------------------------------------------------------------------------------- behaviour probe
-- First step towards Survival's own (learning) enemy behaviour (BUILD_PLAN; tools/re/AI_BEHAVIOURS.md). One test,
-- three questions (CFG.probe):
--  1. Does an enemy run our own behaviour script? The first flight of every round flies a copy of Mission 22's MiG-29
--     whose pursue slot is LA_SV_ProbePursue (barrel roll right, then left, then the stock pursuit, every attack run):
--     odd rounds the script from Survival's package (/Game/LuaSource/SurvivalMode/AI), even rounds a LuaScript object made
--     here at run time from Scripts/ai/LA_SV_ProbePursue.lua. Rows: DT_NPC_LuaSet NLID_SV_ProbePkg/Rt (copies of
--     NLID_0000_CP) and DT_NPC SV_m29a_ProbePkg/Rt (OP1020_m29a_01) are added here at run time, as early as the main
--     menu; the mission rows sv_probe_pkg/rt are in Survival's own NPC table (tools/build_survival.py NPC_EXTRA),
--     because the spawner caches that table's aircraft when the level starts. A variant is only flown when its rows
--     were in before the level loaded.
--  2. Does a live write to an enemy's PilotRank stick? Each enemy's rank is logged, set to CFG.probe.rank, and read
--     again 10 s later.
--  3. Can a kill be attributed? Each enemy's last attacker (K2_GetLastDamagedByAttacker), the aspect and the player's
--     ammo use in the seconds before it went down are logged.
PROBE_TABLES = {
    { key = "luaset",  path = "/Game/Datatables/AI/NPC/LuaSet/DT_NPC_LuaSet.DT_NPC_LuaSet",
      src = "NLID_0000_CP",   row = "NLID_SV_Probe" },
    { key = "npc",     path = "/Game/Datatables/AI/NPC/DT_NPC.DT_NPC",
      src = "OP1020_m29a_01", row = "SV_m29a_Probe" },
}
PROBE_MISSION_ROW = { Pkg = "sv_probe_pkg", Rt = "sv_probe_rt" }   -- in DT_SV_NpcMission (build time)
-- The game's require("A.B.C") loads the LuaScript at /Game/LuaSource/A/B/C with StaticLoadObject and runs its Code
-- (AceCombat8.exe 0x144eb8ce0), so the packaged script sits at that path. The run-time one is put straight into the
-- game's Lua (package.loaded, section "the game's own Lua"), so its LuaScript object only carries the module name.
PROBE_PKG_SCRIPT = "/Game/LuaSource/SurvivalMode/AI/LA_SV_ProbePursue.LA_SV_ProbePursue"
PROBE_PKG_MODULE = "SurvivalMode.AI.LA_SV_ProbePursue"
PROBE_RT_MODULE  = "SurvivalMode.AI.LA_SV_ProbePursueRt"
PR = { ready = {}, usable = {}, scripts = {}, tries = 0, ammo = {} }   -- rows stay in the tables across levels
SR = { ready = {}, usable = {}, tries = 0 }   -- enemy search rows (section "enemy search" below)
-- Difficulty spikes (CFG.spikes): the level of round `round` (0 = none yet), its settings, and its rows' suffix.
SPIKE_SUFFIX = { [0] = "", "b", "c", "d" }      -- tools/build_survival.py SPIKE_SUFFIXES
-- CFG.aces' airframes per tier (tools/build_survival.py ACES, same keys) and their rows: a lead and a wing mission row
-- (sv_ace_<tier>_<key>_l / _w, with _sv[b|c|d] copies like the search aircraft), DT_NPC rows SV_Ace_<tier>_<key>_L / _W
-- (DT_SV_NpcRows, added at the main menu) and text keys SV_Ace_<tier>_<key> (the ace) / SV_Sqn_<tier> (the squadron).
ACE = {
    roster = { mercenary = { "f15c", "su35", "typhoon" }, legend = { "su47", "rafale" }, demon = { "f22a", "su57" },
               phantom = { "su57", "typhoon", "su47" }, reaper = { "su57", "f22a", "typhoon", "rafale", "adfx02" },
               anomaly = { "f04e" },               -- the Anomaly's MINDRIPPER and guards (not a tier: never a flight's)
               glitch = { "e18g" },                -- AB.L..IN (CFG.specials.glitch; not a tier either)
               valka = { "x40a" } },               -- VALKA (CFG.specials.valka; not a tier either)
    row = function(tier, key, part) return "sv_ace_" .. tier .. "_" .. key .. "_" .. part end,
    -- airframes from Online Mode (tools/build_survival.py ACE_MODELS): their model row (DT_SV_ModelRows) goes into the
    -- campaign's DT_NPC_Model first, and their name (the model's GameObjectDisplayName01) is Survival's text
    models = { adfx02 = { row = "SV_Model_adfx", key = "SV_Ac_adfx", name = "ADFX-02" } },
    model_rows = "/Game/Mods/SurvivalMode/Data/DT_SV_ModelRows.DT_SV_ModelRows",
    model_table = "/Game/Datatables/AI/NPC/Model/DT_NPC_Model.DT_NPC_Model",
}
-- The ace squadrons' blink spots (behaviour roadmap P9, CFG.aces.flight <tier>.blink and the "blink" opener; build data,
-- outside CFG: tools/survival_events.py WRAITH_BLINK_*, whose build checks these): RE_SV_WraithBlink<K><J>, K the
-- flight's pool index as a letter (A = ERA_Unit_01_Dep_Air0), J the bearing's (A = 0 deg, world: 0 = +X, AB.L..IN's
-- convention), every STEP_DEG round, RING_M from the player at their height, facing them; one set per flight of the
-- ROLE group (its lead, object 0, only: the squadrons that blink fly that group's flights, and the events stay few).
ACE.BLINK = { STEP_DEG = 45, RING_M = 1000, ROLE = "duelist" }
function spikeLevel(round)
    local sp = CFG.spikes
    if not sp.enabled or not round or round < 1 or #sp.levels == 0 then return 0 end
    return math.min(#sp.levels, #SPIKE_SUFFIX, (round - 1) // math.max(1, math.floor(sp.every)))
end
function spikeCfg(level) return level > 0 and CFG.spikes.levels[level] or {} end
-- The difficulty level the enemies of round `round` fly (their fire-control rows, rank_min, post_stall_all, provoke,
-- aircraft_add): the intensity director's (CFG.intensity.level, sv_director.lua DIR.level: spikeLevel's the ceiling, at
-- most level.max_drop under it while the room's been under heavy pressure), else spikeLevel's
function levelFor(round)
    if DIR and DIR.level then
        local ok, l = pcall(DIR.level, round)
        if ok and type(l) == "number" then return l end
    end
    return spikeLevel(round)
end
-- The tier index (CFG.tiers.list) a flight spawning in round `round` flies: the round's, one higher at promote_chance.
-- The skill tiers (CFG.tiers): TIER.index(round) the round's own tier, TIER.pick(round) that or (promote_chance) the
-- one above it, TIER.pay(base, i) a kill's zollars at tier i (CFG.credits.tier_pay, rounded to 10) and its multiplier.
TIER = {}
function TIER.index(round)
    local i = 1
    for k, t in ipairs(CFG.tiers.list) do if math.max(round or 1, 1) >= t.from_round then i = k end end
    return i
end
-- How many rounds `round` is past CFG.late.from_round (0 before it, 1 in it), or 0 when CFG.late is off.
function TIER.lateRounds(round)
    local l = CFG.late
    if not (l and l.enabled and round) then return 0 end
    return math.max(0, round - l.from_round + 1)
end
-- The chance a pilot flies one tier above the round's: CFG.tiers.promote_chance, plus CFG.late's growth.
function TIER.promoteChance(round)
    local l, n = CFG.late, TIER.lateRounds(round)
    local p = CFG.tiers.promote_chance
    if n > 0 then p = math.max(p, math.min(l.promote_max or 1, p + (l.promote_per_round or 0) * n)) end
    return p
end
-- An enemy aircraft's health multiplier in round `round` (CFG.late), 1 before it.
function TIER.lateHealthX(round)
    local l, n = CFG.late, TIER.lateRounds(round)
    if n <= 0 then return 1 end
    return math.min(l.health_max_x or 1, 1 + (l.health_per_round or 0) * n)
end
-- Late rounds' growth (CFG.late aircraft_from_round on; behaviour roadmap P8): how many rounds `round` is into it (0
-- before it, 1 in it), or 0 when CFG.late or its grow is off or aircraft_from_round is 0. Pure maths of CFG
-- (tools/checks/late_rounds_test.lua reproduces the thesis' table with these).
function TIER.growRounds(round)
    local l = CFG.late
    if not (l and l.enabled and l.grow ~= false and round and (l.aircraft_from_round or 0) > 0) then return 0 end
    return math.max(0, round - l.aircraft_from_round + 1)
end
-- The most aircraft round `round` brings, before the menu's ENEMY AIRCRAFT % and co-op: CFG.max_aircraft, from
-- late.aircraft_from_round aircraft_per_round more a round up to late.max_aircraft (never below CFG.max_aircraft)
function TIER.roundCap(round)
    local l, n, cap = CFG.late, TIER.growRounds(round), CFG.max_aircraft
    if n > 0 then cap = math.max(cap, math.min(cap + (l.aircraft_per_round or 0) * n, l.max_aircraft or cap)) end
    return cap
end
-- Round `round`'s aircraft: aircraft_round1, aircraft_per_round more a round and the difficulty spike's aircraft_add,
-- within the round's cap (the thesis: "spikes still add their aircraft_add on top, within the cap"). level: the spike
-- level whose aircraft_add counts (startRound's levelFor: the intensity director's), default spikeLevel(round)'s
function TIER.roundBudget(round, level)
    local sk = spikeCfg(level or spikeLevel(round))
    return math.min(CFG.aircraft_round1 + (round - 1) * CFG.aircraft_per_round + (sk.aircraft_add or 0), TIER.roundCap(round))
end
-- A co-op room's most aircraft in round `round` (COOP.more's cap, sv_rounds.lua startRound): CFG.coop.max_aircraft,
-- grown by as many as one player's round cap has grown (TIER.roundCap), up to late.coop_max_aircraft (never below
-- coop.max_aircraft): rounds 1-25 keep co-op's 60 whatever the room's size (the thesis: "rounds 15-25 keep today's
-- cap"), then 63, 66 ... 80 by round 32 with the shipped settings
function TIER.coopCap(round)
    local base = tonumber(CFG.coop and CFG.coop.max_aircraft) or CFG.max_aircraft
    local grow = TIER.roundCap(round) - CFG.max_aircraft
    if grow <= 0 then return base end
    return math.max(base, math.min(base + grow, tonumber(CFG.late.coop_max_aircraft) or base))
end
-- The most fighters a round can field: the pool's flights (CFG.pool; 2 / 4 / 6-ships by their _AirN suffix, as
-- sv_spawn.lua flightSize) less the probes' (CFG.probe.units, never picked): 86 with the shipped settings. A raid's
-- bombers come on top. Past it a round flies "pool short" (sv_rounds.lua); the menu's ENEMY AIRCRAFT help stops there.
function TIER.poolMost()
    local probe, n = {}, 0
    for _, u in pairs(CFG.probe and CFG.probe.units or {}) do probe[u] = true end
    for _, u in ipairs(CFG.pool) do
        if not probe[u] then n = n + (({ ["0"] = 2, ["1"] = 4, ["2"] = 6 })[u:sub(-1)] or 2) end
    end
    return n
end
-- The most aircraft a wave of round `round` holds at preset `preset` (casual / standard / ace), before the menu's % and
-- co-op: CFG.waves max_up_by_preset (or max_up), from late.aircraft_from_round max_up_per_round more a round up to
-- late.max_up_cap[preset] (never below the preset's own; a preset without a cap doesn't grow)
function TIER.maxUp(round, preset)
    local w, l, n = CFG.waves, CFG.late, TIER.growRounds(round)
    local up = (w.max_up_by_preset and w.max_up_by_preset[preset]) or w.max_up
    local cap = nil
    if n > 0 and type(l.max_up_cap) == "table" then cap = tonumber(l.max_up_cap[preset]) end
    if cap then up = math.max(up, math.min(up + (l.max_up_per_round or 0) * n, cap)) end
    return up
end
-- The game's player-attack throttle preset round `round` asks for (CFG.late.pressure): the preset of the latest
-- from_round band it's in, "B" (ATTACK_BASE, the mission start's) before them; nil when CFG.late or its pressure is
-- off (then nothing is fired). Letters only of TIER.PRESSURE_PRESETS, tools/survival_events.py PRESSURE (its build
-- checks the two agree), any case in survival.ini. TIER.PRESSURE_OWN: the specials whose event records set their own
-- throttle and put B back as they end (none fired in their round; sv_rounds.lua, sv_coop.lua hostSync).
TIER.PRESSURE_PRESETS = "ABCD"
TIER.PRESSURE_OWN = { anomaly = true, valka = true }
function TIER.pressure(round)
    local l = CFG.late
    local pr = l and l.pressure
    if not (l and l.enabled and type(pr) == "table" and pr.enabled and round) then return nil end
    local want, at = "B", -math.huge
    local froms, presets = type(pr.from_round) == "table" and pr.from_round or {}, type(pr.preset) == "table" and pr.preset or {}
    for i, r in ipairs(froms) do
        local x = type(presets[i]) == "string" and presets[i]:upper() or ""
        if type(r) == "number" and round >= r and r >= at and #x == 1 and TIER.PRESSURE_PRESETS:find(x, 1, true) then
            want, at = x, r
        end
    end
    return want
end
-- The fighter roles' build data (behaviour roadmap P1, CFG.roles; tools/re/BEHAVIOUR_DIRECTOR.md unit 5), outside CFG so
-- survival.ini and co-op's settings can't change it: ROLE_BY_FLIGHT[NN] is pool flight NN's role (ERA_Unit_NN_Dep_Air0-2,
-- tools/survival_events.py ROLE_BY_FLIGHT, which its build checks against this), ROLE.ROWS each role's behaviour row
-- (DT_SV_NpcMission; the Wolf trap's too) and ROLE.SETS its behaviour set (CFG.behaviour_sets), ROLE.LANCER_TOP_M the
-- Lancer flights' altitude band top (survival_events.LANCER_MAX_ALT_M, checked the same way). ROLE.of[unit] = its role,
-- ROLE.units[role] = its flights. Pure maths here; what a level has and the draw are sv_spawn.lua's.
ROLE_BY_FLIGHT = { "duelist", "duelist", "lancer", "lancer", "wolf", "wolf", "skirm", "skirm" }
ROLE = { LIST = { "duelist", "lancer", "wolf", "skirm" },
         ROWS = { lancer = "sv_role_lancer", wolf = "sv_role_wolf_lead", wolf_wing = "sv_role_wolf_wing", skirm = "sv_role_skirmish" },
         SETS = { duelist = "NLID_SV_Fighter", lancer = "NLID_SV_Lancer", wolf = "NLID_SV_WolfLead", wolf_wing = "NLID_SV_WolfWing",
                  skirm = "NLID_SV_Skirmisher" },
         LANCER_TOP_M = 9000, of = {}, units = {} }
for nn, r in ipairs(ROLE_BY_FLIGHT) do
    ROLE.units[r] = ROLE.units[r] or {}
    for k = 0, 2 do
        local u = string.format("ERA_Unit_%02d_Dep_Air%d", nn, k)
        ROLE.of[u] = r
        ROLE.units[r][#ROLE.units[r] + 1] = u
    end
end
-- A Wolf flight's object k is the trap (held until sprung, the trap's row): the odd ones (survival_events.wolf_held).
function ROLE.wolfHeld(k) return type(k) == "number" and k % 2 == 1 end
-- The role weights round `round` draws by: in an ace round (ace true, or its tier's key) the squadron's own roles (P9's
-- ace personalities: CFG.aces.flight <tier>.roles, band "ace:<tier>") or CFG.roles.ace_mix (band "ace"), else mix's band
-- of the latest from_round the round has reached (no band yet: duelists only). Returns { role = weight } and the band.
function ROLE.mixFor(round, ace)
    local c = CFG.roles
    local w = {}
    local pc = CFG.aces and CFG.aces.personality
    local fl = type(ace) == "string" and CFG.aces.enabled and type(pc) == "table" and pc.enabled ~= false
        and type(CFG.aces.flight) == "table" and CFG.aces.flight[ace]
    if type(fl) == "table" and type(fl.roles) == "table" then
        local any = false
        for _, r in ipairs(ROLE.LIST) do
            w[r] = math.max(0, tonumber(fl.roles[r]) or 0)
            if w[r] > 0 then any = true end
        end
        if any then return w, "ace:" .. ace end
        w = {}                                       -- (every weight 0: ace_mix's)
    end
    if ace and type(c.ace_mix) == "table" then
        for _, r in ipairs(ROLE.LIST) do w[r] = math.max(0, tonumber(c.ace_mix[r]) or 0) end
        return w, "ace"
    end
    local m = type(c.mix) == "table" and c.mix or {}
    local froms, band, at = type(m.from_round) == "table" and m.from_round or {}, nil, -math.huge
    for i, r in ipairs(froms) do
        if type(r) == "number" and (round or 1) >= r and r >= at then band, at = i, r end
    end
    for _, r in ipairs(ROLE.LIST) do
        local list = type(m[r]) == "table" and m[r] or {}
        w[r] = band and math.max(0, tonumber(list[band]) or 0) or (r == "duelist" and 1 or 0)
    end
    return w, band and at or nil
end
-- `n` aircraft shared out by weights `w` in whole 2-ships: each role its whole share, the pairs left to roles drawn by
-- what's left of theirs (so over many rounds each gets its share: round 1's two 2-ships at 0.6 / 0.2 / 0.2 are a
-- duelist pair and a duelist, Lancer or Wolf pair 60 / 20 / 20 %, not always the same one). { role = aircraft }.
-- Weights all 0: every pair to the duelists.
function ROLE.quotas(n, w)
    local pairs2, total, q, rest = math.floor((n or 0) / 2), 0, {}, {}
    for _, r in ipairs(ROLE.LIST) do total = total + (w[r] or 0) end
    if total <= 0 then w, total = { duelist = 1 }, 1 end
    local given = 0
    for _, r in ipairs(ROLE.LIST) do
        local exact = pairs2 * (w[r] or 0) / total
        q[r] = math.floor(exact)
        given = given + q[r]
        if exact > q[r] then rest[#rest + 1] = { r = r, f = exact - q[r] } end
    end
    for _ = 1, pairs2 - given do
        if #rest == 0 then q.duelist = q.duelist + 1
        else
            local tot = 0
            for _, x in ipairs(rest) do tot = tot + x.f end
            local pick, roll = #rest, math.random() * tot
            for i, x in ipairs(rest) do roll = roll - x.f; if roll <= 0 then pick = i; break end end
            q[rest[pick].r] = q[rest[pick].r] + 1
            table.remove(rest, pick)
        end
    end
    for r, v in pairs(q) do q[r] = v * 2 end
    return q
end
-- Airframe `a`'s role by CFG.roles.aircraft (the first role that lists it), or nil.
function ROLE.ofAircraft(a)
    local ac = CFG.roles and CFG.roles.aircraft
    if type(ac) ~= "table" then return nil end
    for _, r in ipairs(ROLE.LIST) do
        for _, x in ipairs(type(ac[r]) == "table" and ac[r] or {}) do if x == a then return r end end
    end
    return nil
end
function TIER.pick(round)
    local tc, i = CFG.tiers, TIER.index(round)
    if i < #tc.list and math.random() < TIER.promoteChance(round) then i = i + 1 end
    return i
end
-- Kill pay's round multiplier (CFG.credits round_x_per_round / round_x_max).
function TIER.roundX(round)
    local c = CFG.credits
    return math.min(c.round_x_max or 1, 1 + (c.round_x_per_round or 0) * math.max(0, (round or 1) - 1))
end
function TIER.pay(base, i)
    local tp = CFG.credits.tier_pay or {}
    local x = (i and (tp[i] or tp[#tp])) or 1
    return math.floor(base * x / 10 + 0.5) * 10, x
end
-- An ace round (CFG.aces first_round / every): the round's tier's squadrons only.
-- An ace round (CFG.aces first_round / every; never a special round): the tier index whose squadrons fly it (the
-- round's tier, or the first one above it that has squadrons), or nil.
function aceRound(round, special)
    local a = CFG.aces
    if special or not (a.enabled and CFG.tiers.enabled and round >= a.first_round
        and (round - a.first_round) % math.max(1, math.floor(a.every)) == 0) then return nil end
    local ti = TIER.pick(round)
    for k = ti, #CFG.tiers.list do if ACE.roster[CFG.tiers.list[k].name:lower()] then return k end end
    return nil
end
function withLevel(base, over)                    -- a copy of `base` with `over`'s fields
    local t = {}
    for k, v in pairs(base) do t[k] = v end
    for k, v in pairs(over or {}) do t[k] = v end
    return t
end

function readScript(file)
    local f = io.open(SCRIPT_DIR .. "ai\\" .. file, "r")
    if not f then return nil, "Scripts\\ai\\" .. file .. " not found" end
    local code = f:read("a"); f:close()
    return code
end

---------------------------------------------------------------------------------------------------- the game's own Lua
-- dlls/main.dll 0.8.0 (tools/re/GAME_LUA.md): SV_GameLua(code, name) runs a chunk in the game's Lua 5.3, the state
-- its AI behaviour scripts are built in, and returns "<status>\t<result>"; SV_GameLuaState() its address (0 while
-- the game has none). The plugin swallows every error in a behaviour script (its log is stripped from the shipping
-- game), so Survival installs a small helper there (SV_Instrument / SV_Report) that wraps a behaviour class's Ctor:
-- each build is counted and each error kept with its traceback (then raised as before). Run-time scripts are put in
-- package.loaded under their module name, which require() returns before it looks for an asset at all.
GLS = { L = 0, injected = {}, report = nil, created = false }
GAME_LUA_HELPER = [=[
SV_B = SV_B or { built = {}, errors = {}, nerr = 0 }
function SV_Instrument(name, C)
    if type(C) ~= "table" or rawget(C, "__sv_wrapped") then return C end
    local ctor = rawget(C, "Ctor")
    if type(ctor) == "function" then
        rawset(C, "Ctor", function(self, ...)
            SV_B.built[name] = (SV_B.built[name] or 0) + 1
            local ok, err = xpcall(ctor, debug and debug.traceback or tostring, self, ...)
            if not ok then
                SV_B.nerr = SV_B.nerr + 1
                if #SV_B.errors < 20 then SV_B.errors[#SV_B.errors + 1] = name .. ": " .. tostring(err) end
                error(err, 0)
            end
        end)
    end
    rawset(C, "__sv_wrapped", true)
    return C
end
function SV_Report()
    local t = {}
    for k, v in pairs(SV_B.built) do t[#t + 1] = k .. " x" .. v end
    table.sort(t)
    -- ("all fine" rather than "errors 0": the ACE8 Mod Launcher showed every such line flagged, user 2026-10-30)
    local s = "built " .. (#t > 0 and table.concat(t, ", ") or "nothing yet") .. "; "
        .. (SV_B.nerr == 0 and "all fine" or (SV_B.nerr .. " failed"))
    for i, e in ipairs(SV_B.errors) do s = s .. "\n    [" .. i .. "] " .. e end
    return s
end
return "helper in"
]=]
GAME_LUA_DIAG = [=[
local function ty(f) local ok, v = pcall(f); return ok and type(v) or ("error: " .. tostring(v)) end
local n, ai = 0, 0
for k in pairs(package.loaded) do n = n + 1; if type(k) == "string" and k:find("^Chronicle%.AI%.") then ai = ai + 1 end end
return table.concat({ _VERSION, "io " .. type(io), "os " .. type(os), "debug " .. type(debug),
    "Inherit " .. ty(function() return Inherit end), "CppObjectBase " .. ty(function() return CppObjectBase end),
    "ELiveAIManeuverSpeedType " .. ty(function() return ELiveAIManeuverSpeedType end),
    "modules loaded " .. n .. " (" .. ai .. " Chronicle.AI)" }, ", ")
]=]
-- Stock scripts instrumented too, to compare: the root tree of every enemy plane and the two pursue scripts in use.
GAME_LUA_STOCK = { "Chronicle.AI.LA_AIPlane", "Chronicle.AI.LA_PursueTarget_0011", "Chronicle.AI.LA_PursueTarget_0400",
                         "SurvivalMode.AI.LA_SV_MoveAway", "SurvivalMode.AI.LA_SV_TailChase",
                         "SurvivalMode.AI.LA_SV_ProvokeNear", "SurvivalMode.AI.LA_SV_Escape",   -- ours too: builds and errors
                         -- (the fighter roles', P1: each shows as built once a role flight's desc names its set)
                         "SurvivalMode.AI.LA_SV_LancerPass", "SurvivalMode.AI.LA_SV_LancerZoom",
                         "SurvivalMode.AI.LA_SV_LancerBreak", "SurvivalMode.AI.LA_SV_WolfDrag",
                         "SurvivalMode.AI.LA_SV_WolfStrike", "SurvivalMode.AI.LA_SV_SkirmPass",
                         "SurvivalMode.AI.LA_SV_SkirmExtend" }
REQUIRE_AND_WRAP = "local ok, C = pcall(require, %q); if ok then SV_Instrument(%q, C) end; " ..
                         "return tostring(ok) .. ' ' .. tostring(C)"

function gameLua(code, name)
    if type(SV_GameLua) ~= "function" then return false, "no SV_GameLua (dlls/main.dll older than 0.8.0)", -5 end
    local r = SV_GameLua(code, name or "SurvivalMode")
    local st, res = tostring(r):match("^(%-?%d+)\t(.*)$")
    st = tonumber(st)
    return st == 0, res or tostring(r), st
end
