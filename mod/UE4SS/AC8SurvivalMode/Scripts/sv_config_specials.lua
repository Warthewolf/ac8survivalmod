-- sv_config_specials.lua: CFG's last settings, each a statement of its own from `CFG = {` (sv_config.lua): CFG.specials
-- (every special round's; its fields from GONE FISHIN''s on, with CFG.sky, CFG.music and CFG.hud, go on in
-- sv_config_arc.lua). Piece 2 of 5 of sv_config.lua's family (sv_config.lua, sv_config_specials.lua, sv_config_arc.lua,
-- sv_config_subs.lua, sv_config_ini.lua), split by tools/lua_split_part.py and run by main.lua right after the piece
-- before it: a name another part uses is a global of this mod's Lua state, its own helpers stay local.
CFG.specials = {
    enabled  = true,
    random   = true,
    chance   = 0.3,
    first    = 4,
    every    = 5,
    -- ("spaceport", the Spaceport Assault, in the rotation from 0.73.73 (user, 2026-11-02: "install spaceport into the
    -- new patch"); from its own from_round; its retake comes the round after a lost one) ("escort", THE ESCORT,
    -- 2026-11-06: once a run, from its own from_round, and only when its units are in the build: sv_escort.lua)
    -- ("fishing", GONE FISHIN', from 0.74.0: once a run, from its own from_round; THE FESTIVAL is never drawn: it's the
    -- round its arc puts six rounds after it, sv_spawn.lua specialFor; "decoy" is added just after this table)
    rotation = { "shuttle", "anomaly", "amphibious", "ladon", "alicorn", "glitch", "valka", "spaceport", "escort", "fishing" },
    -- an early special (user, 2026-10-23: "buff the chances of the shuttle spawning between rounds 2 and 6"): in
    -- rounds from .. to, each round is `kind` with `chance` (before `first` too), under the same rules (never two
    -- specials in a row, not the same one twice running), and no other special comes in those rounds: the
    -- random picks above start after `to` (user: only the Shuttle Launch may come between 2 and 6).
    early    = { kind = "shuttle", from = 2, to = 6, chance = 0.35 },
    -- ((2026-11-08) the user's plan: "Round 2 always Shuttle Launch. Round 6 always Charlene's Escort Mission. Round 9
    -- Always Gone Fishin. Then the festival at its usual round ... everything else is free game for the special rounds
    -- after the festival they can come in any order and in any way") schedule: its rounds' specials for sure (one that
    -- can't come, switched off or not in the build: a normal round), no other special before THE FESTIVAL's round
    -- (GONE FISHIN''s + festival.round_after: round 15), the dice above after it (`early` unused); fixed_again: whether
    -- the scheduled kinds can be drawn after it too (the Shuttle Launch: THE ESCORT and GONE FISHIN' are once a run).
    -- enabled = false: the dice from `first`, the early window, as before.
    schedule = { enabled = true, rounds = { [2] = "shuttle", [6] = "escort", [9] = "fishing" }, fixed_again = false },
    -- each special comes at most once in this many rounds (user, 2026-10-23): Comona Defense in round 2 can come
    -- again from round 12; the others keep their chance meanwhile. 0: no cooldown.
    cooldown_rounds = 10,
    -- the random specials' pacing (0.73.80; the 31-round test of 0.73.79: rounds 7-13 had none, 4 of the 8 kinds never
    -- came): each round rolled with no special since the last one adds chance_step to `chance` (at most 0.9; an ace
    -- round or a round no special could come in doesn't count), and after max_gap of them the next one rolled is a
    -- special for sure (0: never sure; both x / the menu's SPECIAL ROUNDS); bag: the kinds come from a shuffle bag of
    -- the rotation's, each once before any comes again (false: an even draw each time); swap: a special that can't
    -- start (no landing craft lane, its fleet's rows, the shuttle's last one still up) is swapped for another that can
    -- (false: a normal round, as before)
    chance_step = 0.15, max_gap = 4, bag = true, swap = true,
    -- specials scale with the round (economy review of 2026-10-25: "all five were beaten easily, in 2.8-4.4 minutes.
    -- A special late in the run should bring escorts and more health, like the normal rounds around it"): from
    -- escort_from, the specials named in escort_kinds (which fly alone) bring escort_share of the round's aircraft
    -- as fighter flights (escort_min..escort_max). Their health grows by their own health_per_round.
    -- Not the Ladons (user, 2026-10-25: "during a ladon round, only the ladon's spawn, no other aircraft should").
    escort_from = 12, escort_share = 0.25, escort_min = 2, escort_max = 8,
    escort_kinds = { "alicorn", "glitch" },
    -- ((2026-11-07) the user: "Anomaly Rounds shouldn't start until Charlene arrives at the airbase btw, That Includes,
    -- Valka, Mindripper, Abelcain" and the lightning Anomaly) the kinds in `kinds` (and a special whose own settings say
    -- wait_for_charlene) aren't drawn until CHARLENE has landed at Comona (THE ESCORT, RUN.escort.arrived;
    -- sv_escort_subs.lua ESC.anomalyOk). They don't wait when THE ESCORT can't come this run (switched off, out of the
    -- rotation, its rows or units not in the build); after_lost: once she's been shot down (the escort failed), they
    -- come anyway, without her warning (false: never in that run). A test key's forced special never waits. Her warning
    -- the round before one (the user: "the round before an Anomaly Round appears, a Subtitle from Charlene should appear
    -- telling the Players that an Anomaly Is Approaching (she will not be able to warn players about VALKA though)"): at
    -- the round's end, the next round's special drawn then, for the kinds in warn_kinds, her lines
    -- CFG.specials.escort.text.say.warn_<kind> (or the special's own charlene_warn)
    anomaly_gate = { enabled = true, kinds = { "anomaly", "glitch", "valka" }, after_lost = true,
                     warn = true, warn_kinds = { "anomaly", "glitch" } },
    -- "alicorn" = the ALICORN (tools/survival_events.py ALCN_*; docs/re/ALICORN.md; user, 2026-10-23: "start
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
    -- Its core, as it opens, takes core_missiles of your standard missiles for one player and core_missiles_per_player
    -- more for each other player flying then (a co-op host: itself if it's up, not DOWN and not down at the airfield,
    -- and the others flying; solo: just you), more a round as the tanks' (user, 2026-11-11: "Yes add the alicorns core
    -- size"; it had ~60 missiles' health whoever flew). x the round's growth (round 45: x3.05), 10 + 3.3 a player is ~30
    -- alone and ~61 for four there, the agreed numbers (a full room as before, alone half): never more than before at
    -- any round for up to four players flying (each one past four adds 3.3 more). The missile's damage unread, or
    -- core_missiles 0: health_x as before.
    -- Its rows are Online Mode's (DT_SV_Alcn*): `tables` adds them to the campaign tables at the main menu.
    -- Debuffed across the board (user, 2026-10-23: "way too strong"; were 110 / 30 / 25 / 35 / 25, health x0.5,
    -- +0.04 a round, at most x1.5): shorter dives, its first shot later, railgun and volleys less often, less health.
    -- (health_per_round 0.05, health_max_x 1.4: were 0.03 / 1.0, economy review of 2026-10-25)
    -- It counts as surfaced once it's back within surfaced_m of where it sailed (the order sent again every
    -- resurface_s while it isn't rising, resurface_tries times at most; up anyway after up_wait_s).
    -- rail_alert (behaviour roadmap P3/P7, docs/re/BEHAVIOUR_DIRECTOR.md unit 4): Mission 18's RAILGUN WARNING on
    -- every game (RE_SV_AlcnAlertOn, forwarded) with the railgun's tell (CFG.tells alcn_rail, its lead_s before the
    -- order), off alert_s after the order (it aims ~7 s and preps ~2 s: docs/re/ALICORN.md), at a dive and when it
    -- sinks (hard rule 45); false: no warning (the tell still comes with tells on). After a surfacing the warning
    -- comes no sooner than radio_gap_s after "submarine has surfaced" (the order its lead after it). Once you've
    -- destroyed both railguns: the warning off, no more warnings, tells or orders; every VLS: no more VLS calls or
    -- volleys (code review of 2026-10-29)
    -- deck (behaviour roadmap P7, "surfaced phase spawns Skirmishers from its deck"; docs/re/BEHAVIOUR_DIRECTOR.md
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
                core_missiles = 10, core_missiles_per_player = 3.3,
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
                 -- around you; a third phase drops ECM and goes all-out guns"; docs/re/BEHAVIOUR_DIRECTOR.md unit 9).
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
    valka    = { enabled = true, name = "VALKA", squadron = "MIHALY'S SHADOW", unit = "SV_Unit_Valka", health = 2000,
                 health_per_round = 0.04, health_max_x = 2.5, reward = 9000, reward_per_round = 300, ai_level = 5,
                 disguise = true, decoy_share = 0.5, decoy_min = 2, decoy_max = 6, lurk_s = 4,
                 anomaly_line = "CATASTROPHIC LEVEL ANOMALY", big_x = 2.0,
                 -- ((2026-11-07) the user: Valka "has outbursts where she becomes the full anomaly version of herself
                 -- (the X-02S anomaly)"; AUDREY breaking in on the radio, "ADD IT THIS IS GOOD STUFF OMG") her round's
                 -- subtitles (sv_anomalies_valka.lua V.subs, lines as THE ESCORT's: "WHO|text", C / T / G Comona's staff):
                 -- reveal as she shows (reveal_charlene too once CHARLENE's at Comona: she can't warn of VALKA), AUDREY
                 -- at her health under each hurt_at mark (audrey_<n>), down as she's shot down (down_charlene too)
                 text = { say = { hurt_at = { 60, 30 },
                                  reveal = { { "C|Comona Control: a contact out of nowhere! Nothing on radar before it!" },
                                             { "C|What is that? It wasn't on any scope. It wasn't anywhere." } },
                                  reveal_charlene = { { "CHARLENE|My sensors read nothing. Nothing at all. That isn't possible." },
                                                      { "CHARLENE|I couldn't see her coming. Pilots, I'm so sorry." } },
                                  audrey_60 = { { "AUDREY|Valka? Valka, it's me. Come back to me.",
                                                  "C|Unknown voice on this frequency. ...Who is that?" },
                                                { "AUDREY|Valka, can you hear me? It's Audrey. It's okay. Come back.",
                                                  "C|Unidentified transmission. Who's on this channel?" } },
                                  audrey_30 = { { "AUDREY|Valka, listen to my voice. You're not that. You're mine. Come home." },
                                                { "AUDREY|Pilots, bring her down. Gently. She doesn't know what she's doing." } },
                                  down = { { "AUDREY|...There you are. I've got you, Valka. Let's go home.",
                                             "C|The contact's gone. Signal lost. ...Whoever that was." },
                                           { "AUDREY|Valka? Valka. Yes. It's me. I've got you now.",
                                             "C|Signal lost. Comona Control, logging it as... nothing." } },
                                  down_charlene = { { "CHARLENE|...Whoever she was, I think someone just took her home." } } } },
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
                 -- WPO, character base); (their old test key is gone: Ctrl+9 is the ZFA-44 test T0)
                 -- (0.73.76) the screen fades to red as she shows and back after she dies (sv_hud.lua hudRed)
                 -- (the sky, not the screen: sv_hud.lua hudRed; user, 2026-11-03 "red sky instead of red screen",
                 -- "turn the sky more red"): strength how far towards these (0-1), in_s / out_s; the level's sun light
                 -- and sky light colours (0-1), its height fog's (Comona's is off: 0, so a faint haze), and the sky
                 -- params' sun colour (normally 1 1 1; more than 1 is brighter: it colours the whole dome)
                 red = { enabled = true, strength = 1.0, in_s = 3, out_s = 5, sun = { 1, 0.25, 0.15 },
                         light = { 1, 0.3, 0.2 }, fog = { 0.1, 0.012, 0.006 }, sky_sun = { 1.8, 0.3, 0.15 } },
                 -- (0.73.76) her song (the user's own track, in their VALKA build only: Sounds\valka\Void.wav, staged by
                 -- VALKA=1 package_dev.sh from build/valka_music): with the red, at volume (linear), faded out after her death
                 song = { enabled = true, file = "valka/Void.wav", volume = 1.0, loop = true, out_s = 5, game_music = "mute" },
                 paint = 16,            -- (0.73.76 15: the x40a's gear material, the Falken add-on's way; 11: AC8's character master)
                 -- her swing wings: unswept below sweep_kmh[1], swept above [2] (AC7's), a full travel in sweep_s
                 -- (0.67.1-0.67.6 had it off: its keys went in without the AC7 -> UE axis change, and her wings came
                 -- apart in game; tools/x02s/ue_import.py ue_quat converts them now)
                 sweep_anim = "/Game/Mods/SurvivalMode/Valka/Model/A_X02S_Valka_Sweep", sweep_kmh = { 800, 1000 },
                 sweep_s = 2.5, hit_radius_m = 10,
                 -- the opener's flash: flash_layers copies of it at once (its light adds up), flash_scale big (user,
                 -- 2026-10-24: "put that further away and turn its brightness up a lot ... it was quite hard to see")
                 flash = "/Game/VFX/Mission/Mission023/NS_ms23FarFlash", flash_scale = 12.0, flash_s = 3.0, flash_layers = 4,
                 -- ((0.73.77) plan D5; the user, 2026-11-03, with a screenshot: her arrival's flash covered most of the
                 -- screen) the lens flash's elements below are sized as shares of the screen, so it's as big at 14 km as
                 -- close by: each one's size x flash_size_x (1: AC7's own; 0.5 halves them)
                 flash_size_x = 0.5,
                 -- the opener's light as AC7 Mission 18's lens flash (user, 2026-10-24: "rebuild the Effect that Mihaly
                 -- uses when it spawns in on Mission 18"; ms18_LensEffect1, tools/x02s builds it): screen-space billboard
                 -- elements { name, size (fraction of the screen) } on AC8's own flare, faded over life_s along AC7's
                 -- alpha curve (time fraction, alpha), intensity_x times the stock flare's brightness. If it doesn't
                 -- load, the flash above shows instead.
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
                 eml_life_s = 8, opener_miss_up_m = 250,   -- ((0.73.76) 30 -> 8: they lived too long)
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
    -- stays theirs alone, user 2026-10-25, so no escorts; docs/re/BEHAVIOUR_DIRECTOR.md unit 9): one shot down, the
    -- other is enraged: its volleys every rage.volley_every_s (the first first_s on, rage.volley_warn_s in range),
    -- and from the end of the arc it's on it goes round its circuit at the build's faster speed
    -- (tools/survival_events.py LADON_RAGE_SPEED: RE_SV_LadonRage<Key> sets its flag, the PathFinish records pick the
    -- speed; 0.73.73: the same circle, its old tighter rage circuit was never flown). false: as before
    -- (back on in 0.73.60, user 2026-11-01: "turn the Ladon's back on as well as VOID WATCHER" to test them)
    -- enabled = false (hotfix4, user 2026-11-01: "turn off VOID WATCHER and the LADON Rounds"): no Ladon round
    -- until their paths are fixed in a build (the enraged one's rage circuit isn't followed)
    ladon = { enabled = true, names = { Kot = "KOT", Mishka = "MISHKA" }, health_add = -800, speed_x = 1.0, bomb_damage = 20,
              bomb_per_round = 1, health_per_round = 0.05, health_max_x = 2.5,
              -- rage.circuit false (hotfix3): no switch to the rage circuit (RE_SV_LadonRage<Key>). The host's run of
              -- 2026-10-31 17:43: MISHKA, enraged, took it at its next pass and flew a straight line east, 87 km
              -- out and below sea level, until it was down: the rage path isn't followed. It keeps its own circuit.
              -- (0.73.73: true now only speeds it up round its own circle, LADON_RAGE_SPEED; not yet tried in game)
              rage = { enabled = true, volley_every_s = 25, volley_warn_s = 0, first_s = 5, circuit = false },
              volley_every_s = 45, volley_range_km = 8, volley_warn_s = 10, volley_gap_s = 22,
              -- volley_after_pass false: no VLS volleys once a Ladon has made its first pass over the airfield
              -- (patch ladon1, 2026-10-31: on its circuit, each volley re-fired its appearance, which sent it
              -- back onto its route from the far west: "the Ladon decided to leave the map"). Its CIWS / pulse
              -- cannons and its bombing runs stay. true: as before. pos_log_s: its position in the log every N s.
              -- (0.73.73: its appearance's records now run once a spawn, so a fire again can't restart its route;
              -- not yet tried with volleys on: true for a test, the log says when it fires again)
              volley_after_pass = false, pos_log_s = 15,
              -- (0.73.73) the backstop: a Ladon leash_km or more from the airfield after its first pass is off its
              -- circuit (which keeps it within ~17 km): taken off its path, its unit area onto the airport, where it
              -- circles (RE_SV_LadonLeash<Key>), at most every leash_every_s. 0: off
              leash_km = 22, leash_every_s = 90,
              missile_damage = 10, missile_homing_x = 0.85, missile_turn_x = 0.5,
              reward = 6000, reward_per_round = 200,
              npc_rows = "/Game/Mods/SurvivalMode/Data/DT_SV_NpcRows.DT_SV_NpcRows" },
    -- "amphibious" = Amphibious Assault (docs/design/SURVIVAL_SPEC.md 7; tools/survival_events.py LCAC_*): landing craft on
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
    -- "spaceport" = the Spaceport Assault (docs/re/SPACEPORT_ASSAULT.md, tools/survival_events.py SP_*; the user's
    -- special of 2026-10-31; Scripts/sv_spaceport.lua): an enemy fleet west of the spaceport, `ships` of each kind
    -- (the build has 1 Ford, 4 Wasps, 14 Aegis and 8 missile boats; fewer leaves the last of a kind out),
    -- spawn_per_tick of them every 0.5 s. Each Wasp afloat sends 2 landing craft every wave_every_s (the first
    -- first_wave_s after the fleet appears); each craft that lands puts a troop vehicle ashore (invincible this
    -- round), which drives to the spaceport: capture_per_troop % of its capture each, taken off troop_stay_s after it
    -- gets there (gone in), or troop_timeout_s after it landed if it never does; a wave's craft are taken off
    -- remove_after_s after the first one landed. At 100 % the spaceport is captured: no more landings, and the next
    -- round is the retake. Every ship sunk with nothing still coming in: held, reward + reward_per_round x the
    -- round. pay: zollars a ship (by kind) or landing craft destroyed. fighter_share: the round's fighters, of its
    -- aircraft. from_round: never before this round. ford_cm: the Ford's spot and heading (x, y cm, yaw deg:
    -- survival_events.sp_fleet), for its deck when its hull can't be read.
    -- enabled = false: no Spaceport Assault and no retake, forced or not (tools/nospaceport.py: friends' builds without
    -- them, NOSPACEPORT=1; user, 2026-10-31)
    spaceport = { enabled = true, from_round = 8, ships = { ford = 1, wasp = 4, aegis = 14, boat = 8 }, spawn_per_tick = 3,
                  wave_every_s = 180, first_wave_s = 20, capture_per_troop = 10, troop_stay_s = 30,   -- (capture 5 -> 10: user, 2026-11-02)
                  troop_timeout_s = 420, remove_after_s = 60, fighter_share = 0.5, reward = 10000,
                  -- (0.73.77, the economy's C2: a ship pays its price once, when its hull goes; turret: a turret
                  -- shot off while its hull floats, the landing craft's rate. Before, price x every part lost)
                  reward_per_round = 300, pay = { ford = 3000, wasp = 1200, aegis = 800, boat = 300, craft = 150, turret = 150 },
                  ford_cm = { -2964629, -26491, 3.0 },
                  -- the turrets' own fire control (sv_spaceport.lua SPORT.FLEET_ROWS; as CFG.allies.ships' fcs, on
                  -- top of CFG.allies.fcs; the user, 2026-10-31: "up the Activation Range and Targetting Range and
                  -- Lifetime of ALL Ships"): search_m their AI module's reach (stock turrets 6000), range_x their
                  -- lock-on range, round_reach their guns' rounds out to it, missile their homing missiles' lock-on
                  -- range_m, flight life_s, acceleration x accel_x, top speed, turn x turn_x; lock_x / fire_x 2.0
                  -- undo CFG.allies.fcs.time_x 0.5 (their stock rate of fire)
                  -- (user, 2026-10-31: "increase the lock on and firing distance of all SAM sites and Ships":
                  -- search 25 -> 40 km, the guns' lock-on x2 -> x3, the missiles 20 -> 35 km, 30 -> 45 s, 3600 km/h)
                  -- (2026-10-31: "increase Ship AA gun accuracy": gun_spread_x, round_width_x 1.0 -> 1.5; salvo_x
                  -- 0.8, homing_from, flak: the STORE Aegis's (CFG.allies.ships.Aegis.fcs): the Aegis's Mk 45 and the
                  -- Ford's four mounts flak guns, the missiles homing as the EXSAM's)
                  fcs = { lock_x = 2.0, fire_x = 2.0, range_x = 3.0, search_m = 40000, slew_x = 1.5, round_reach = true,
                          round_width_x = 1.5, gun_spread_x = 0.5,
                          flak = { enabled = true, fcs = "NPC_FCS_FlakGun000", range_m = 15000, damage_x = 2.0, min_alt_m = 50,
                                   fire_x = 0.5 },
                          missile = { range_m = 35000, life_s = 45, accel_x = 1.5, speed_max_kmph = 3600, turn_x = 1.0,
                                      salvo_x = 0.8, homing_from = "EXSAM_Ground_000", salvo_n = 3, salvo_gap_s = 0.5 } },
                  -- the Ford's deck, as the Alicorn's (CFG.specials.alicorn.deck): from first_s, a free size-ship
                  -- pool flight every every_s, flights + flights_per_round x the round (at most max_flights), max_up
                  -- of them up at once, ahead_m off its bow and alt_m up
                  -- (user, 2026-10-31: "increase the Carriers aircraft spawn rate": first_s 45 -> 20, every_s 50 -> 25,
                  -- max_up 2 -> 4, flights 3 -> 5, flights_per_round 0.15 -> 0.3, max_flights 8 -> 14)
                  -- (0.73.77, the plan's I8: reserve, the deck's flights held back from the round's fighters when
                  -- the round is planned and launched first, each again once it's down; 0: none, as before. Round
                  -- 13's fighters took every free 2-ship and the deck launched 2 of 8)
                  deck = { enabled = true, first_s = 20, every_s = 25, size = 2, max_up = 4, flights = 5,
                           flights_per_round = 0.3, max_flights = 14, ahead_m = 600, alt_m = 1100, reserve = 4 },
                  -- (user, 2026-11-04: "in the spaceport assault round, can you please add TU-160's that come from both
                  -- the North and the south to target the airfield and bomb it", then "spawn everytime a WASP gets
                  -- destroyed, have 4 bombers each") tu160: each Wasp sunk in the assault sends a group of `group`
                  -- Tu-160s (on `aircraft`) delay_s later, the groups taking `bearings` in turn (compass from the
                  -- airfield: 0 north, 180 south; the first by chance), within spread_deg of it, distance_km out. A group
                  -- is the heavy bomber flights (CFG.airfield.bombers.heavy_units: the build's 2-ship and 4-ship) adding
                  -- up to `group`; while they're still up from the last group, the next waits for them. They fly the
                  -- heavies' route in over the runway and bomb it as a raid's heavies do (CFG.airfield.bombers drop_km,
                  -- bomb_damage), they're paid as heavies, and the round ends only once they're down too. None after a
                  -- capture, in the retake, or with the airfield off (CFG.airfield.enabled); a group's delay waits while
                  -- you're down at the airfield, as the waves' clocks do.
                  tu160 = { enabled = true, aircraft = "t160_common", group = 4, delay_s = 6, bearings = { 0, 180 },
                            spread_deg = 10, distance_km = { 28, 34 } },
                  -- the retake, the round after a captured spaceport: the garrison (a unit of 4 targetable vehicles
                  -- for every per_unit troop vehicles that got in, 3 at most) and the ships still afloat; reward +
                  -- reward_per_round x the round when they're all down, garrison_pay a vehicle; fighter_share of the
                  -- round's aircraft. enabled = false: no retake (0.73.77: the fleet left afloat is taken off at the
                  -- lost assault's end). test_troops: the troops Ctrl+INS's forced retake counts (test only).
                  -- rockets (Scripts/sv_spaceport.lua's rockets; the user, 2026-10-31: "can you please build the rockets
                  -- this time?"): Mission 19's two, launched launch_a_s / launch_b_s into the retake, boosted boost_s on,
                  -- rocket_pay each shot down; one reaching 20.2 km escapes: escape_penalty zollars and no reward; the
                  -- last one shot down breaks up (debris = false: it doesn't), each stage of its debris targetable in
                  -- turn (debris_tgt_s after the kill, debris_next_s after each stage), debris_pay a piece, taken off
                  -- debris_timeout_s after the last change
                  -- (0.73.77, the plan's I5: a rocket neither shot down nor escaped timeout_s after its launch is
                  -- taken off, no penalty; an escape counts only from escape_min_m up (a climb that ends lower is
                  -- taken off, no penalty); the last one's debris only once its split is seen, split_wait_s at most)
                  retake = { enabled = true, per_unit = 4, reward = 12000, reward_per_round = 300, garrison_pay = 300,
                             fighter_share = 0.6, test_troops = 8,
                             -- (island: the island's air defences and armour, ad_pay / armour_pay each; extra_aircraft
                             -- fighters on top of fighter_share; user, 2026-10-31: "add more enemies around the island":
                             -- air defences, armour, more aircraft)
                             extra_aircraft = 6, island = { enabled = true, ad_pay = 600, armour_pay = 400 },
                             rockets = { enabled = true, launch_a_s = 45, launch_b_s = 110, boost_s = 12, rocket_pay = 3000,
                                         escape_penalty = 5000, debris = true, debris_tgt_s = 3, debris_next_s = 2.8,
                                         debris_pay = 400, debris_timeout_s = 120,
                                         timeout_s = 240, escape_min_m = 15000, split_wait_s = 10,
                                         -- ((2026-11-11) Saint Alessia's run, both rockets escaped: "10000% need to add the
                                         -- mission dialogue about stopping the rocket launch, froya didn't even notice";
                                         -- "Use the Mission 22 radio lines for the rocket warning") at the rockets' spawn,
                                         -- warn_s before each launch, at its liftoff, halfway up (half_m), its escape and its
                                         -- kill: a big callout (big_x), Comona Control's line (subs: a list's lines in
                                         -- turn, one not said yet this run; {rocket}, {s}, {b}, {km} filled in) and Mission
                                         -- 22's countdown on the radio (radio = false: none); its height on the NEXT row
                                         warn_s = 15, half_m = 10100, big_x = 1.5, radio = true, log_s = 10,
                                         subs = {
            brief = { "CTRL|Two enemy rockets on the pads: rocket A launches in {s} seconds, B in {b}. Shoot them down before orbit!",
                      "CTRL|They're launching from the pads we lost. First rocket in {s} seconds. Don't let either one reach orbit!" },
            warn = { "CTRL|Rocket {rocket}'s count is running: liftoff in {s} seconds. Get over the pads!",
                     "CTRL|Ignition sequence on rocket {rocket}! {s} seconds to liftoff!" },
            launch = { "CTRL|Liftoff! Rocket {rocket} is climbing. Bring it down before it reaches orbit!",
                       "CTRL|Rocket {rocket} is away and climbing fast! Get after it!" },
            half = { "CTRL|Rocket {rocket} is {km} km up, halfway to orbit. Shoot it down now!",
                     "CTRL|Rocket {rocket}'s halfway up! This is your last chance to stop it!" },
            escaped = { "CTRL|Rocket {rocket} made it out of the atmosphere. We lost it.",
                        "CTRL|Too late, rocket {rocket}'s in orbit. That one's going to cost us." },
            down = { "CTRL|Rocket {rocket} is down! It isn't going anywhere.", "CTRL|Direct hit on rocket {rocket}! Good work!" } } } } },
    -- "decoy" = THE DECOY (Scripts/sv_decoy.lua, docs/re/DECOY.md; user, 2026-11-06): a Marker UAV far north (the
    -- bait: its Tonitrus Spear guidance laser painting the airfield, pinged on the minimap) the players must shoot down;
    -- then the trap: up to max_total UAVs come round the players (spawn_km from one, any bearing, alt_m of their
    -- height, never inside safe_km of the runway, gap_km from another, at most per_player_max within near_km of a
    -- player and max_up at once, one a player every spawn_every_s), each locking its closest player (lock_after_s
    -- after it shows; its laser searches lock_delay_s, then that player has lock_s to shoot it down before the Spear
    -- is called onto them; relock_s after the call it locks its closest player again). The Spear (Mission 19's rod: a
    -- ~3 s fall from 58 km, 200 damage direct, 30 a graze, a blast growing 200 -> 900 m) aimed at the player, led by
    -- their velocity (lead: the rod's PredictionTime, fall_s), never at a player inside safe_km or DOWN; sure_kill:
    -- the stock sure kill (Mission 26's LiveDestroyPlayerPlaneExecution) once the rod lands (off: the rod's own
    -- damage). The bait springs the trap when it's down, or anyway bait_timeout_s after it shows (0: never; its clock
    -- stops while everyone's down at the airfield). The trap ends with all max_total down, every living player inside
    -- safe_km for safe_hold_s (from safe_after_s into it; its reward x reward_safe_x), or trap_s. Pays the bait, each
    -- UAV and the reward (+ *_per_round x the round; a co-op special's pay: [zollars] special_split). fighter_share of
    -- the round's aircraft fly as fighters too (0, the default since 2026-11-07, the user: "make sure that in the GONE
    -- FISHIN round and THE DECOY that normal aircraft arent spawning": the decoy alone). From from_round; once a run.
    -- Units and records: the build's (tools/survival_events.py), named below; a build without them never rolls it.
    -- dt_npc: the trap UAVs' DT_NPC row (DT_SV_NpcRows' weaponless Marker UAV), added at the main menu (DECOY.setup:
    -- before the level loads, hard rule 20); without it no DECOY round (the bait's and the Spear's rows are stock)
    decoy    = { enabled = true, from_round = 10, once_per_run = true, name = "SHOOT DOWN THE RECON DRONE", fighter_share = 0,
                 dt_npc = "SV_DecoyUav",
                 bait_unit = "SV_Unit_DecoyBait", bait_mark = "SV_Unit_DecoyBaitMark", bait_timeout_s = 240,
                 ping_every_s = 12, uav_prefix = "SV_Unit_DecoyUav_", mark_prefix = "SV_Unit_DecoyMark_", uavs = 40,
                 spear_prefix = "SV_Unit_DecoySpear_", spears = 4,
                 -- ((2026-11-08) the user: "Total UAV's in solo 12 and in Coop +4 per player with a max of 40")
                 total_solo = 12, total_per_player = 4,
                 max_total = 40, max_up = 12, per_player_max = 4, near_km = 8.0, spawn_every_s = 4.0,
                 spawn_km = { 2.5, 5.0 }, alt_m = 1000, min_alt_m = 600, max_alt_m = 9000, gap_km = 1.5,
                 safe_at = { 1610476, -436142 }, safe_km = 5.0, edge_km = 2.0,
                 -- ((2026-11-07) Alyssa's test: the Spear every 2-4 s) at most locks_per_player locks on a player at
                 -- a time (user: "Only two UAV's can lock onto a player at a time"), each lock_gap_s after the last
                 -- one on them (their strikes that far apart: 10, the user: "have the strikes come every 10 seconds
                 -- with the UAVs"), a UAV relock_s after its own strike
                 lock_after_s = 2.0, lock_delay_s = 1.5, lock_s = 8.0, relock_s = 1.0, imminent_s = 3.0,
                 -- ((2026-11-08) the user: a "Ring on the UAV locking you" on the minimap) its ping every ping_lock_s
                 -- while its lock on you counts down (RE_SV_DecoyPing_NN; 0: never)
                 ping_lock_s = 2.0,
                 locks_per_player = 2, lock_gap_s = 10.0,
                 designate_s = 40.0, arm_wait_s = 10.0,
                 trap_s = 300, safe_hold_s = 5.0, safe_after_s = 30,
                 sure_kill = false, impact_wait_s = 8.0,
                 -- the rod's lead: fall_s (its PredictionTime; she measured 1.0-2.3 s), learnt from each impact
                 -- (learn: the median of the last learn_n, min_s .. max_s)
                 lead = { enabled = true, fall_s = 1.6, learn = true, learn_n = 7, min_s = 0.8, max_s = 3.0 },
                 -- the hit judged by Lua (the stock rod ends at sea level, never at a plane's height): a strike hits
                 -- with `chance` while you hold the line you flew at the call, less the farther you broke off it, none
                 -- from dodge_m off (user, 2026-11-07: "should also be able to miss the players sometimes"); judge =
                 -- false: the rod alone. A hit takes damage_pct of your max health (user, 2026-11-07: "heavy damage",
                 -- not a kill); one that leaves nothing kills you (RE_SV_DecoyKill) unless can_kill = false (1 HP left);
                 -- damage_pct 100: every hit a kill, as before
                 hit = { judge = true, chance = 0.6, dodge_m = 200, damage_pct = 50, can_kill = true },
                 -- the clouds (2026-11-07: they warped with every strike): mode "hole" = the user's own mod's fix
                 -- (the blast at the clouds' height, height_m or midway up the two lowest layers; the sky's
                 -- ExplosionEffect as below, put back restore_after_s after the Spear's quiet), "off" = no cloud blast,
                 -- "stock" = as the game has it
                 -- the Spear's blast (2026-11-07, the user's texture list: Mission 25's cutscene Rods-from-God
                 -- explosion, the stock systems below): `air` at a judged strike at the player's height, `ground` where
                 -- the bait's strike lands on the airfield, x scale; enabled = false: the game's own effects only
                 blast = { enabled = true, scale = 1.0,
                           air = { "/Game/VFX/IGC/Ms25/Ms250010/NS_IGCVFX_Ms250010_Explosion001",
                                   "/Game/VFX/IGC/Ms25/Ms250010/NS_IGCVFX_Ms250010_ShockWave001" },
                           ground = { "/Game/VFX/IGC/Ms25/Ms250010/NS_IGCVFX_Ms250010_Explosion001",
                                      "/Game/VFX/IGC/Ms25/Ms250010/NS_IGCVFX_Ms250010_ShockWave001",
                                      "/Game/VFX/IGC/Ms25/Ms250010/NS_IGCVFX_Ms250010_SandSmoke001",
                                      "/Game/VFX/IGC/Ms25/Ms250010/NS_IGCVFX_Ms250010_RingSmoke001" } },
                 -- the bait's Spear on the airfield (its laser's: the game's own strike as it goes down) takes damage
                 -- off the airfield (its 250 HP; a bomber's bomb 10) where it lands within within_km of the bait's mark,
                 -- or at the mark wait_s after a rod showed with none seen landing (user, 2026-11-07: "it does no damage
                 -- to the airfield")
                 bait_strike = { enabled = true, damage = 40, within_km = 2.5, wait_s = 8 },
                 clouds = { mode = "hole", every_s = 5, restore_after_s = 60, radius_km = 3.0, weld_km = 2.0,
                            fade_km = 24.0, whirl = 0.001, push = 0.12, cirrus_fade_km = 7.3, expand_s = 5.0,
                            expand_p1 = 2.775, expand_p2 = 0.892, contract_s = 50.0, contract_p1 = 0.14 },
                 pay = { bait = 2000, bait_per_round = 50, uav = 300, uav_per_round = 10 },
                 reward = 6000, reward_per_round = 200, reward_safe_x = 0.5,
                 recycle_after_s = 4.0, recycle_gap_s = 1.0,
                 -- radio (the build's clones of the stock lines into DT_SV_Radio): `lock` "laser targeting!" as a lock
                 -- on you starts, `imminent` "strike imminent!" imminent_s before the soonest strike, `incoming` "Tonitrus
                 -- Spear incoming!" as one's called, `hit` "took a direct Spear hit!" when it hurt you, `brief` "projectiles
                 -- will hit locations marked by the laser" as the trap springs; gap_s between any two, each its cooldown
                 radio = { enabled = true, gap_s = 2.5, lock_s = 10, imminent_s = 6, incoming_s = 6, hit_s = 10 } },
    -- "escort" = THE ESCORT (Scripts/sv_escort.lua, docs/re/ESCORT.md; user, 2026-11-06): the allied B-1B CHARLENE
    -- and her four escorts (YORKE and ROCK, Su-57s; ALI, a Su-33; DANIELLE, a Su-35) fly in from the map's south-west
    -- corner (start, 3 km up) to Comona airfield under the round's waves and land: her route (RE_SV_CharGo), then by
    -- distance her final (RE_SV_CharFinal, gear down), rollout, taxi and stop; the escorts hold their wait orbits
    -- (SV_Path_EscOrbit_<Name>: a 6 km circle north of the extended centre line, touching it 4 km before the approach
    -- fix) once she's on final and come in one at a time after her, each released onto its final as it passes the
    -- circle's touching point heading the runway's way (release_gap_s apart, each once the runway is clear). The
    -- round ends only once everyone left has landed or she's lost. Her loss fails the special (no reward,
    -- no unlock; the run goes on). All landed (an escort shot down is out, not waited for): reward + reward_per_round
    -- x the round, her subtitle and the ZFA-44 carriers unlocked in the STORE for the rest of the run (the room's in
    -- co-op: CFG.allies.carrier). Once a run (once), from from_round, in the rotation's bag; a build without its units
    -- in the world data never picks it (SV_UnitAlive answers "no such unit"). Unit, record and name-key names: the build
    -- contract of 2026-11-06 (tools/build_survival.py, tools/survival_events.py).
    -- ((2026-11-07) the user: CHARLENE "is a Wealthy CEO who owns one of the worlds largest plane collections, she is
    -- from the KOKODA MERCENARY GROUP, based out of Aurelia"; "Yorke, Rock, Ali, Danielle are also apart of KOKODA
    -- MERCENARY GROUP ... they should each have a squadron tag KMG, as well as Charlene") tag: on each one's target box,
    -- as tag_format (the tag, then the name; "": the name alone)
    escort = { enabled = true, from_round = 9, once = true, name = "CHARLENE", airframe = "B-1B",
               tag = "KMG", tag_format = "[%s] %s",
               unit = "SV_Unit_Charlene", name_key = "SV_CharleneCall", rec = "RE_SV_Char",
               -- the escorts' DT_NPC rows (DT_SV_NpcRows' copies of the plain Su-57 / Su-33 / Su-35 on their allied
               -- models), added at the main menu (ESC.setup: before the level loads, hard rule 20); without them no
               -- ESCORT round (her row is the stock OP0008_b01b_Ally_01)
               dt_npc = { "SV_Esc_Su57", "SV_Esc_Su33", "SV_Esc_Su35" },
               -- her health x health_x once she's up (the B-1B's 130 is two missiles' worth); the escorts are scaled as
               -- the STORE's allied aircraft (CFG.allies.aircraft.scale)
               health_x = 4.0,
               -- (each escort: its unit, name key and record prefix <rec><Go|Orbit|Final|Roll|Taxi|Stop|...>, whose tail
               -- names its leg and slot flags, SV_EscLeg<Name> / SV_TaxiSlot<Name>; right_m / up_m: its start beside
               -- her, right_m to her right (negative: left) across her way to the approach fix and up_m above her, as
               -- the build's routes have it (tools/survival_events.py ESC_ESCORTS: km right, km up; none behind). Each
               -- one's route starts there, so a spawn anywhere else crosses her track at the route's speed (code review
               -- of 2026-11-07: the old side / back signs put each on the wrong side). Where each parks is the build's:
               -- the next free slot in landing order, geo.slots)
               escorts = {
                   { name = "YORKE", airframe = "SU-57", unit = "SV_Unit_EscYorke", name_key = "SV_Yorke",
                     rec = "RE_SV_EscYorke", right_m = 600, up_m = 100 },
                   { name = "ROCK", airframe = "SU-57", unit = "SV_Unit_EscRock", name_key = "SV_Rock",
                     rec = "RE_SV_EscRock", right_m = -600, up_m = 100 },
                   { name = "ALI", airframe = "SU-33", unit = "SV_Unit_EscAli", name_key = "SV_Ali",
                     rec = "RE_SV_EscAli", right_m = 1200, up_m = 250 },
                   { name = "DANIELLE", airframe = "SU-35", unit = "SV_Unit_EscDanielle", name_key = "SV_Danielle",
                     rec = "RE_SV_EscDanielle", right_m = -1200, up_m = 250 },
               },
               -- where they appear: (x, y) cm, z cm, heading (compass) towards the approach fix (her yaw); the escorts
               -- at their right_m / up_m, across the exact way from here to geo.iaf; each one's route record
               -- go_delay_s after its spawn
               start = { x = -4110000, y = 3140000, z = 300000, heading = 55, go_delay_s = 1.0 },
               reward = 8000, reward_per_round = 300,
               -- the round's enemy aircraft x budget_x
               budget_x = 1.0,
               -- enemy flights sent after her: of the round's fighter flights (not an ace squadron's, a bomber, the
               -- jammer's or a raid escort) up after_s, `share` of them (at most `max` at once) get each plane's
               -- EngagementOrderOverride onto her (Normal, TargetFirst), again every again_s, kept out of the squad
               -- director's and co-op's hunts; back on you once she's on the ground or lost
               attack = { enabled = true, share = 0.6, max = 4, after_s = 4, again_s = 10 },
               -- ((2026-11-09) the user: "we need to scale the enemies by players") in co-op the host's room gets more:
               -- attack.max, waves.min_n / max_n and waves.max_up x co-op's aircraft_per_player for each player past the
               -- first (COOP.more; max_up within [coop] max_up), as a round's aircraft are; false: as a solo run's
               coop_scale = true,
               -- the round's flights spawned ahead of her (share of them, km ahead along her heading, within side_km of it)
               ahead = { enabled = true, share = 0.5, km = 15, side_km = 6 },
               -- ((2026-11-07) the user: "Keep spawning Multiple enemy fighters until she lands, have them range from 4
               -- to 12 aircraft spawning per wave in different directions") while she flies (her route and her final),
               -- a wave every every_s (the first first_s after her spawn) of min_n .. max_n aircraft (free pool flights:
               -- 2-, 4- and 6-ships, one shot down flies again), from one of eight directions round her, never the last
               -- wave's nor one next to it (km out, its flights spread_deg apart, alt_m up); held while max_up enemy
               -- aircraft are up; max_waves 0: no limit. Each goes after her (attack)
               waves = { enabled = true, first_s = 20, every_s = 45, min_n = 4, max_n = 12, max_up = 24, max_waves = 0,
                         km = { 12, 16 }, spread_deg = 12, alt_m = { 2500, 4000 } },
               -- the escorts on her attackers: every every_s each escort's planes onto an enemy near her (within km of her).
               -- records: from the first enemy within km of her on, each escort on its route also flies the build's
               -- cover (<rec>Guard, Mission 14's way of keeping units on its C-130: off its route, Normal, air search,
               -- its unit area onto her at 3 km), given again every record_every_s (its area follows her) until her
               -- final, when they go to their wait orbits; false: they stay on their routes (the orders alone)
               guard = { enabled = true, every_s = 4, km = 8, records = true, record_every_s = 6 },
               -- the landing, by distance (metres) and speed (km/h): final_at_m from the approach fix her final; the
               -- rollout within roll_at_m of the touchdown point (or past it and under 20 m); the taxi within taxi_at_m of
               -- the rollout's end (or under taxi_kmh near it); the stop within stop_at_m of its parking spot (or taxi_max_s
               -- on); landed under landed_kmh for landed_hold_s (or stop_max_s on). ((2026-11-07) Her route runs on
               -- into her final and the rollout, one path, given again at each new speed: Mission 14's way.) The
               -- escorts hold over her from her final (their area on her at 4 km); with the runway clear and
               -- release_gap_s since the last, the first holding escort with the landing circuit's start
               -- (geo.circuit_start, heading geo.circuit_heading) circuit_min_m .. circuit_max_m ahead, within
               -- circuit_nose_deg of its nose, heading within circuit_hdg_deg of the circuit's, takes it (hard rule 2);
               -- none lined up in hold_max_s: started anyway. An escort's slow-downs only on the final leg (final_leg_m
               -- of the centre line, heading the runway's way). Her approach: farther from the touchdown than her
               -- closest by recover_m (over 2 km out): her path given again, recover_max times recover_gap_s apart.
               -- track_s: a line with everyone's place that often from her final on. Speeds (the build's records, the
               -- path given again): her route at 450 km/h from cruise_slow_km of the touchdown (RE_SV_CharCruiseSlow,
               -- her escorts' too), each final at 280 from final_slow_km and 260 from final_short_km (<rec>FinalSlow
               -- / FinalShort; 0: never).
               -- Safety: one not landed land_timeout_s after its final is
               -- counted as landed (taken off if it's still flying); route_max_s on her route, then her final anyway;
               -- the whole escort max_s (then everyone up counted landed). Times count only while the world runs (not
               -- while you're down at the airfield with nobody else flying). avoid_off_km: within that of the touchdown
               -- her obstacle avoidance off (EnableAvoidObstacle false; 0: never); close_airfield: landing closed to the
               -- players while one of them is within close_km on the final leg or rolling out, open again reopen_s after
               -- (RE_SV_AirfieldClose / Open; 2026-11-07: it had stayed closed from her final until everyone was down)
               -- ((2026-11-07, the user: "The Landing for Yorke, Charlene, Rock, Ali and Danielle takes WAY TOO long":
               -- 25 minutes, ended on max_s) Faster: her final at 450 until final_slow_km (final_fast: her route
               -- given again at 450, <rec>CruiseSlow, a second after her Final); each one landed once it's taxiing
               -- (landed_at_taxi: its taxi and stop go on by the build's path ends); the escorts all onto the
               -- (shorter, ~14 km) circuit from release_at ("final", "roll" or "landed") + release_first_s, one every
               -- release_gap_s, the first lined up with its start or (none in hold_max_s) the first anyway; an
               -- escort's 280 / 260 only once it's that low on the final leg (escort_slow_up_m / escort_short_up_m: YORKE
               -- had fired its 260 crossing the runway 2.9 km up, and flew the whole circuit at it); after_her_s after
               -- she's landed, each one still up counted as landed (switched off when flying) and the escort won; one
               -- landed that flies again (climb_off_m over the runway or faster than climb_off_kmh: CHARLENE had climbed
               -- away from her taxi to 925 m) switched off
               landing = { final_at_m = 2000, roll_at_m = 350, taxi_at_m = 150, taxi_kmh = 70, stop_at_m = 60,
                           landed_kmh = 5, landed_hold_s = 2, roll_max_s = 90, taxi_max_s = 90, stop_max_s = 20,
                           land_timeout_s = 480, route_max_s = 900, max_s = 1500, release_gap_s = 15, inbound_max_s = 120,
                           ahead_deg = 60, hold_max_s = 0, circuit_min_m = 800, circuit_max_m = 6000,
                           circuit_nose_deg = 50, circuit_hdg_deg = 75, final_leg_m = 700, close_km = 5, reopen_s = 5,
                           track_s = 3, recover_m = 800, recover_gap_s = 20, recover_max = 3,
                           cruise_slow_km = 25, final_slow_km = 6, final_short_km = 2,
                           avoid_off_km = 3, invincible_on_ground = true, close_airfield = true,
                           final_fast = true, landed_at_taxi = true, release_at = "roll", release_first_s = 0,
                           after_her_s = 210, escort_slow_up_m = 450, escort_short_up_m = 250,
                           climb_off_m = 60, climb_off_kmh = 150 },
               -- the build's points (cm; tools/survival_events.py ESC_*, docs/re/ESCORT.md "Build names"): the approach
               -- fix (IAF: her final's start), touchdown, the rollout's end, runway 07's thresholds and heading;
               -- circuit_start / circuit_heading: the escorts' landing circuit's first point (600 m up, 2 km north of the
               -- runway, 0.7 km past its east threshold: the ~14 km circuit of 2026-11-07, tools/survival_events.py
               -- ESC_CIRC_*) and its downwind's compass heading; slots: the five parking slots A-E on the parallel taxiway (metres along runway 07 from its west
               -- threshold and to the right of it, south: the ends of SV_Path_TaxiSlotA-E), taken in landing order (the
               -- Taxi records pick them, SV_TaxiSlot<Who> 1-5: read back where it can be, else counted here)
               geo = { iaf = { 96255, 206608, 84602 }, touchdown = { 1569055, -418560, 750 },
                       roll_end = { 1668467, -460758, 750 }, heading = 67,
                       circuit_start = { 1669669, -678540, 60000 }, circuit_heading = 247,
                       slots = { { 832, 62.5 }, { 912, 62.5 }, { 992, 62.5 }, { 1072, 62.5 }, { 1152, 62.5 } },
                       west = { 1541439, -406838 }, east = { 1679514, -465447 }, runway_z = 750 },
               -- remove_records: at the round's end each one is also taken off by its own <rec>Remove record (Mission
               -- 22's despawn); without them each is switched off (hidden, no collision) and its unit taken off the list
               remove_records = false,
               -- her line once everyone's down (the user's exact text), on the subtitle strip (2026-11-07, the user:
               -- "the Lines about unlocking the ZFA-44 and Charlene Thanking the players also should be subtitles too")
               -- in lines of at most thanks_chars, cut after a comma where it can be (else at words); with the strip
               -- off, callouts of at most subtitle_chars as before
               subtitle = "Thank You Pilot, I've sent word to HQ and they've sent two Cargo Vessels into the Area with the Special ZFA-44 Airframes, you can call for their support from the STORE",
               subtitle_chars = 90, thanks_chars = 125,
               -- the landing test T0 (Ctrl+F5, test builds only): she appears before_m short of the approach fix on the
               -- runway's heading (her final's start a little ahead of her: hard rule 2), its log every log_s, taken off
               -- end_s after she's down
               test = { log_s = 0.5, end_s = 30, before_m = 1500 },
               text = { sub = "ESCORT CHARLENE TO THE AIRFIELD", go = "CHARLENE INBOUND",
                        go_sub = "KMG B-1B AND FOUR ESCORTS FROM THE SOUTH-WEST: GET HER HOME",
                        -- ((2026-11-07) the user: "Charlene, Yorke, Rock, Ali, Danielle all should have their own unique
                        -- Subtitles", "Give Charlene Unique Lines for Landing, Being Attacked, Being Defended") what they
                        -- and Comona's staff say on the subtitle strip (Scripts/sv_escort_subs.lua): "WHO|text", WHO
                        -- one of them by name, or C / T / G the staff (`staff`); {dir}, {name} filled in. A list of
                        -- lines: one of them, never the same twice running and never one of someone shot down; a list
                        -- of lists: one exchange of them, every line in order. go: as she spawns; first_attack: the first
                        -- enemies sent at her; wave: each wave sent at her ({dir}: where from); hit: her health down
                        -- hit_drop points within hit_window_s (once in hit_gap_s); hurt_<n>: her health under n%;
                        -- defended_you / _ally / _staff: an enemy within defended_km of her shot down by a player /
                        -- an allied aircraft (her escorts) / Comona's guns (once in defended_gap_s); final, touchdown,
                        -- her_landed: her landing; crew.<NAME>: each escort's own down and landed lines, escort_down
                        -- the reply ({name}); lost: her loss; won: after her thanks (`subtitle`); warn_<kind>: the round
                        -- before an Anomaly (CFG.specials.anomaly_gate). A line from a list waits at most busy_s for the
                        -- strip, else it isn't said
                        say = { enabled = true, busy_s = 6, hit_drop = 4, hit_window_s = 3, hit_gap_s = 18,
                                hurt_at = { 75, 50, 25 }, defended_km = 5, defended_gap_s = 20,
                                staff = { C = "COMONA CONTROL", T = "COMONA TOWER", G = "CREW CHIEF" },
                                -- ((2026-11-07) the user: "Yorke is the Team Leader of their Squadron, Rock is his 2nd
                                -- in command, Ali and Danielle are dating")
                                go = { { "C|Comona Control to inbound B-1B, identify yourself.",
                                         "CHARLENE|Charlene, Kokoda Mercenary Group, out of Aurelia. Coming in.",
                                         "CHARLENE|She's the rarest airframe in my collection. Not a scratch.",
                                         "YORKE|Yorke, KMG lead. Four of us on her wing.",
                                         "ROCK|Rock, KMG two. In position.",
                                         "ALI|Ali here. Smooth skies so far. I hate smooth skies.",
                                         "DANIELLE|Danielle. Most kills picks dinner. Ali, I'm picking." },
                                       { "C|B-1B on the south-west approach, you're on our scope.",
                                         "CHARLENE|Charlene, Kokoda Mercenary Group. I'm landing at Comona. Today.",
                                         "CHARLENE|There are bandits in this sky, and I am not paying for new paint.",
                                         "YORKE|KMG escort flight, checking in. Yorke leading.",
                                         "ROCK|Rock, two, on her left. Nothing gets through.",
                                         "ALI|Ali, on station. Danielle, you're on my wing. Good.",
                                         "DANIELLE|Danielle, ready. Ali, eyes on the bandits, not on me." },
                                       { "C|Comona Control. Kokoda flight, we have you. Come straight in.",
                                         "CHARLENE|Thank you, Comona. My escorts and I would like a quiet trip.",
                                         "CHARLENE|Pilots, I pay very well for quiet. Do earn it.",
                                         "YORKE|Yorke. Formation's tight. Eyes out. Rock, you have the left.",
                                         "ROCK|Copy, lead. Weapons hot.",
                                         "ALI|Ali. One Su-33, all wings attached. Danielle checked twice.",
                                         "DANIELLE|Danielle here. Send them in, I'm bored." } },
                                first_attack = { "CHARLENE|Bandits closing on me. How terribly rude.",
                                                 "CHARLENE|They're coming for the Lancer. Of course they are. Look at her.",
                                                 "CHARLENE|Hostiles on my nose. Pilots, this is what my money is for." },
                                wave = { "CHARLENE|More of them, from the {dir}! Pilots, please!",
                                         "CHARLENE|Bandits, {dir}. I didn't fly her out of Aurelia to lose her.",
                                         "CHARLENE|Another pack from the {dir}. Someone explain my lawyers to them.",
                                         "CHARLENE|From the {dir} this time. They really do want my collection.",
                                         "CHARLENE|They're coming from the {dir}. Not one of them near my wings.",
                                         "YORKE|New contacts, {dir}! KMG, stay on Charlene.",
                                         "YORKE|Heads up, {dir}! Break them up before they reach her!",
                                         "ROCK|Contacts, {dir}. Lots of them.",
                                         "ALI|Bandits from the {dir}! Somebody's popular today.",
                                         "DANIELLE|More from the {dir}? Good. I was falling behind.",
                                         "C|Comona Control: new hostiles from the {dir}, closing on the B-1B.",
                                         "C|Fresh bandits, {dir}. They're going for the bomber." },
                                hit = { "CHARLENE|I'm hit! That was a very expensive noise.",
                                        "CHARLENE|Something just bounced off my wing. Pilots!",
                                        "CHARLENE|They're shooting at a museum piece! Have they no culture?",
                                        "CHARLENE|Taking fire! Get them off me!",
                                        "CHARLENE|That one hurt. Somebody will be getting an invoice.",
                                        "CHARLENE|Hit again! I own ninety aircraft and none of them have a scratch!",
                                        "CHARLENE|My Lancer is leaking fuel. I am not amused.",
                                        "CHARLENE|They're on my tail! Kokoda, earn your retainer!" },
                                hurt_75 = { { "CHARLENE|Paint damage. My restorers are going to weep.",
                                              "YORKE|Closing up, Charlene. Stay on course." },
                                            { "CHARLENE|Three quarters of my airframe left. Let's keep it that way." } },
                                hurt_50 = { { "CHARLENE|Half my systems are screaming at me. Pilots, earn your fee!",
                                              "ROCK|On it." },
                                            { "CHARLENE|She's badly hurt. I've rebuilt her once. Never again.",
                                              "DANIELLE|Nobody touches her. Got it." } },
                                hurt_25 = { { "CHARLENE|Hydraulics failing! If she goes down, so does your bonus!",
                                              "YORKE|All KMG, collapse on Charlene! Now!" },
                                            { "CHARLENE|I'm barely holding her! Get me to that runway!",
                                              "C|Comona Control: crash crews are standing by, Charlene." } },
                                defended_you = { "CHARLENE|Splendid shot. Remind me to raise your rate.",
                                                 "CHARLENE|That's the kind of work Kokoda pays for. Well done.",
                                                 "CHARLENE|One less pest. Keep them off my wings.",
                                                 "CHARLENE|Beautiful flying. I may have to hire you.",
                                                 "CHARLENE|Bravo. I'd frame that kill if I could.",
                                                 "CHARLENE|Thank you, pilot. That one was a little too close.",
                                                 "CHARLENE|Lovely. Do that again, as often as you like." },
                                defended_ally = { "YORKE|Splash one, off Charlene's six.",
                                                  "YORKE|Bandit down. Close it up, KMG.",
                                                  "ROCK|Got him.",
                                                  "ROCK|Another one. Next.",
                                                  "ALI|Fox two, kill! The navy taught me something after all.",
                                                  "ALI|Splash! Danielle, did you see that?",
                                                  "DANIELLE|Nice one, Ali. Don't let it go to your head.",
                                                  "ROCK|Splash. Lead, her six is clear.",
                                                  "DANIELLE|That's mine. Yorke, count it.",
                                                  "DANIELLE|Splash! Is anybody else keeping score?",
                                                  "CHARLENE|My escorts, everyone. Worth every zollar.",
                                                  "CHARLENE|Good work, Kokoda. That's why you're on retainer." },
                                defended_staff = { "C|Airfield defences got one. You're welcome, Charlene.",
                                                   "G|The base guns got one! Did you see that?" },
                                final = { { "T|Kokoda B-1B, Comona Tower. Runway zero-seven, cleared to land.",
                                            "CHARLENE|Cleared to land. Gear down. Keep them off me on final.",
                                            "YORKE|KMG, hold north of the field. We go in after her." },
                                          { "T|Charlene, Comona Tower. Wind's calm, runway zero-seven is yours.",
                                            "CHARLENE|Lovely. Gear coming down. Three green.",
                                            "DANIELLE|We'll keep the sky clean, Charlene. Go." } },
                                touchdown = { "CHARLENE|Wheels down! My insurers will be thrilled.",
                                              "CHARLENE|Touchdown. Smoother than my last board meeting.",
                                              "CHARLENE|On the runway. Easy, old girl. Easy." },
                                her_landed = { { "CHARLENE|Down and safe. Tell your ground crew: hands off the paint.",
                                                 "G|Crew Chief here. Ma'am, we'll be... very gentle." },
                                               { "CHARLENE|Parked. Someone fetch me a coffee and a damage report.",
                                                 "G|Coffee's on its way, ma'am. The report may take a while.",
                                                 "YORKE|Charlene's down. KMG, one at a time, let's go." },
                                               { "T|B-1B on the ground. Welcome to Comona, Charlene.",
                                                 "CHARLENE|Thank you, Tower. Now bring my people down." } },
                                -- crew.<NAME>: its own down / landed lines; mourn: who answers its loss (said in place of
                                -- escort_down; one who's down never says it)
                                crew = { YORKE = { down = { "YORKE|I'm hit, I'm hit! Ejecting! Rock, you have the lead!",
                                                            "YORKE|Lost an engine... punching out! Rock, she's yours!" },
                                                   landed = { "YORKE|Yorke's down. A good landing, if I say so myself.",
                                                              "YORKE|Lead on the ground. KMG, bring it in clean." },
                                                   mourn = { "ROCK|Lead's out. I have the lead. KMG, on me.",
                                                             "ROCK|Yorke's chute is open. Two has the lead. Tighten up." } },
                                         ROCK = { down = { "ROCK|Hit. Going out.", "ROCK|I'm done. Ejecting." },
                                                  landed = { "ROCK|Down.", "ROCK|Rock, on the ground. Coffee." },
                                                  mourn = { "YORKE|Rock's down! ...Damn it. KMG, tighten up.",
                                                            "YORKE|Lost my two. Rock, you'd better be swimming." } },
                                         ALI = { down = { "ALI|No wire to catch me this time! Ejecting!",
                                                          "ALI|Ali's hit! Danielle, I'm out! I'm okay!" },
                                                 landed = { "ALI|A runway this long feels like cheating. Ali's down.",
                                                            "ALI|Ali's down. Danielle, I'll wait for you on the apron." },
                                                 mourn = { "DANIELLE|Ali!! You'd better be alive down there, I swear.",
                                                           "DANIELLE|Ali's chute... I see it. Okay. Okay. Who did that?!" } },
                                         DANIELLE = { down = { "DANIELLE|They got me! Count my kills, Yorke! Ejecting!",
                                                               "DANIELLE|Danielle's hit! I'm out! Ali, don't you dare follow me!" },
                                                      landed = { "DANIELLE|Danielle on the ground. And I had the most kills.",
                                                                 "DANIELLE|Down. Ali, you owe me that dinner." },
                                                      mourn = { "ALI|Danielle! DANIELLE! ...I see her chute. She's okay.",
                                                                "ALI|They hit Danielle. Right. Nobody leaves this sky." } } },
                                escort_down = { "CHARLENE|{name} is down! Kokoda takes care of its own. Find that chute!",
                                                "CHARLENE|We've lost {name}! Comona, mark that ejection!",
                                                "C|Comona Control: we have {name}'s chute. Rescue is on the way." },
                                lost = { { "CHARLENE|I'm losing her! Ejecting! My beautiful Lancer...",
                                           "C|Comona Control: we've lost the B-1B. The escort has failed." },
                                         { "CHARLENE|Mayday, mayday! She's gone! Kokoda, get me out of here!",
                                           "YORKE|Charlene's out! I see her chute. KMG, cover her!" } },
                                won = { { "C|Two cargo vessels with ZFA-44s inbound. Call VAMPIRES from the STORE.",
                                          "YORKE|Good flying, everyone. KMG owes you one." },
                                        { "C|Confirmed, Charlene. All pilots: VAMPIRES are in the STORE.",
                                          "DANIELLE|For the record, I had the most kills." } },
                                warn_anomaly = { { "CHARLENE|Pilots, Charlene. My sensors are picking up an Anomaly.",
                                                   "CHARLENE|It'll be on you next round. It scrambles your controls." },
                                                 { "CHARLENE|Kokoda's instruments say an Anomaly is approaching.",
                                                   "CHARLENE|Next round. Trust your instincts, not your stick." } },
                                warn_glitch = { { "CHARLENE|Pilots, Charlene. An Anomaly is approaching. Something's off.",
                                                  "CHARLENE|It reads like an EA-18G that isn't quite there. Next round." },
                                                { "CHARLENE|My radar keeps losing something. An Anomaly, next round.",
                                                  "CHARLENE|It jumps around. Don't trust where you think it is." } } },
                        row = "CHARLENE %d%%  %.1f KM  LANDED %d/%d", row_landing = "CHARLENE LANDING  LANDED %d/%d",
                        row_done = "ESCORT: LANDED %d/%d",
                        final = "CHARLENE ON FINAL", final_sub = "KEEP THE APPROACH CLEAR",
                        landed = "CHARLENE HAS LANDED", landed_sub = "%d ESCORTS TO BRING IN",
                        escort_down = "%s IS DOWN", escort_down_sub = "%d ESCORTS LEFT",
                        lost = "CHARLENE IS DOWN", lost_sub = "THE ESCORT FAILED",
                        won = "ESCORT COMPLETE", won_sub = "+%d ZOLLARS: VAMPIRES IN THE STORE" } },
    -- reward_per_round: added to `reward` x the round (2026-10-23: a late special paid less than a normal round)
    shuttle  = { name = "EMBDIR Shuttle - CORRIS", countdown_s = 150, reward = 6000, reward_per_round = 200, strike_share = 0.4,
                 -- pad_allies: Mission 22's pad guns, SAMs and tower around the shuttle during the countdown
                 -- (removed after it, tools/survival_events.py PAD_REMOVE_LOST_S / SHUTTLE_REMOVE_S)
                 -- remove_s: liftoff to the shuttle and pad being taken off; = SHUTTLE_REMOVE_S (its flags reset after it)
                 remove_s = 180,
                 pad_allies = true, dummies = "SV_Unit_PadDummies",
                 shop_closed_rounds = 1, unit = "SV_Unit_Shuttle", pad = "AA_Unit_01_Ground0",
                 name_key = "SV_Shuttle_Name", npc_row = "OP0057_sstb_01_SV",
                 npc_rows = "/Game/Mods/SurvivalMode/Data/DT_SV_NpcRows.DT_SV_NpcRows",
                 -- ((2026-11-08) the user: "Add enemy character subtitles in the Shuttle Launch Special Round", "Kaska is
                 -- not allowed to talk to the players, make it seem that Kaska doesn't know that the players can see his
                 -- conversations" (the user's own script, reviewed line by line) KASKA on an intercepted Emblem Direct
                 -- channel with his launch controller (Scripts/sv_kaska.lua; "KASKA|" / "EMBDIR|": CFG.hud.subs.speakers):
                 -- start as the countdown runs, strike as War's strike flights come up (strike_s at most), marks at
                 -- those seconds left, hit as the shuttle's health falls under each hit_at mark, launched / lost at its
                 -- end, after in the break (after_s on). Each moment one of its lists (an exchange said whole), each line
                 -- once a run; a moment's lines left out while the strip has more than busy_s waiting (marks: mark_busy_s)
                 subs = { enabled = true, strike_s = 30, busy_s = 8, mark_busy_s = 5, after_s = 8, hit_at = { 75, 50, 25 },
                          start = { { "EMBDIR|Sir, the pad is green. Countdown's running.",
                                      "KASKA|Good. Keep this channel closed. The locals don't need to hear us." },
                                    { "KASKA|Is the payload sealed? ...Good. Nobody opens that crate." },
                                    { "KASKA|Comona thinks it's hosting a weather satellite. Let it." } },
                          strike = { { "EMBDIR|Bandits inbound. Not ours, sir.",
                                       "KASKA|War's. Right on time. She was never going to let us fly." },
                                     { "EMBDIR|Sir, those jets carry no markings. Nobody's claiming them.",
                                       "KASKA|They're War's. A wolf in sheep's clothing never signs her work." },
                                     { "KASKA|Of course she's here. She's wanted this launch dead for months." },
                                     { "KASKA|Let Comona's pilots handle them. That's what they're for." },
                                     { "KASKA|She knows what this launch means. She'd burn the island to stop it." } },
                          marks = { { 120, { "KASKA|Tell Sudentor to be ready the moment we're up." } },
                                    { 90, { "EMBDIR|Ninety seconds. Sir, the list from Sudentor came in.",
                                            "KASKA|Read me the names later. I know who's on it." } },
                                    { 60, { "KASKA|Sixty seconds. They've waited years. They can wait a minute." } },
                                    { 30, { "EMBDIR|Thirty seconds.", "KASKA|No mistakes now." } },
                                    { 10, { "KASKA|Ten. ...Open it." } } },
                          hit = { { "EMBDIR|We're taking hits on the pad!",
                                    "KASKA|Then Comona's pilots are slower than I was promised." },
                                  { "KASKA|If the payload cracks, I want to know before anyone else does." },
                                  { "KASKA|War will be watching this feed. Don't give her the data." } },
                          launched = { { "EMBDIR|Clean separation. The satellite's on its way.",
                                         "KASKA|Good. Tell Sudentor the door is on schedule." },
                                       { "KASKA|Wipe the logs. As far as Comona knows, it was a weather bird." },
                                       { "KASKA|Keep those pilots flying. Some of our guests will want a rematch." } },
                          lost = { { "EMBDIR|We lost it, sir. The payload's gone.",
                                     "KASKA|Then build another. The dead have waited this long." },
                                   { "KASKA|Find out who War paid for this. Quietly.",
                                     "EMBDIR|Sir, her people swear they had nothing to do with it.",
                                     "KASKA|They always do. A wolf in sheep's clothing, that one." } },
                          after = { { "KASKA|Close the channel. If anyone was listening, I want their names." } } } },
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
                 gun_accuracy_x = 20, gun_reach_x = 20, gun_life_x = 4,   -- ((0.73.76) its rounds' life x4, not x20)
                 -- and it leads you (user, 2026-10-24: "make MINDRIPPER lead targets with its gun"): it aims where
                 -- you'll be gun_lead_s ahead (PredictionOffsetTime; its rounds fly 833 m/s, so 1 s suits ~0.8 km)
                 gun_lead_s = 1.0,
                 -- its guards' search range: they see you only this close, so they stay circling it and jump you
                 -- when you come near (test of 2026-10-22: with the 40 km search they left it for you and the airfield)
                 guard_search_m = 5000,
                 -- its pack (behaviour roadmap P7: "PHANTASM guards fly as a Wolf pack that springs while your controls
                 -- are scrambled"; docs/re/BEHAVIOUR_DIRECTOR.md unit 9): spring_delay_s after its field scrambles
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
}  -- (CFG.specials goes on in sv_config_arc.lua: its fields from fishing on)
