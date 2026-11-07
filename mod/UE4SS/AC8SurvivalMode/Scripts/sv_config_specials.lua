-- sv_config_specials.lua: CFG's last settings, each a statement of its own from `CFG = {` (sv_config.lua): CFG.specials
-- (every special round's), CFG.sky (the sky and the day-night arc), CFG.music and CFG.hud (the HUD and its texts).
-- Piece 2 of 3 of sv_config.lua (sv_config.lua, sv_config_specials.lua, sv_config_ini.lua), split by
-- tools/lua_split_part.py and run by main.lua right after the piece before it: a name another part uses is a global of
-- this mod's Lua state, its own helpers stay local.
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
    -- stays theirs alone, user 2026-10-25, so no escorts; tools/re/BEHAVIOUR_DIRECTOR.md unit 9): one shot down, the
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
    -- "spaceport" = the Spaceport Assault (tools/re/SPACEPORT_ASSAULT.md, tools/survival_events.py SP_*; the user's
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
                                         timeout_s = 240, escape_min_m = 15000, split_wait_s = 10 } } },
    -- "decoy" = THE DECOY (Scripts/sv_decoy.lua, tools/re/DECOY.md; user, 2026-11-06): a Marker UAV far north (the
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
                 ping_every_s = 12, uav_prefix = "SV_Unit_DecoyUav_", mark_prefix = "SV_Unit_DecoyMark_", uavs = 35,
                 spear_prefix = "SV_Unit_DecoySpear_", spears = 4,
                 max_total = 35, max_up = 12, per_player_max = 4, near_km = 8.0, spawn_every_s = 4.0,
                 spawn_km = { 2.5, 5.0 }, alt_m = 1000, min_alt_m = 600, max_alt_m = 9000, gap_km = 1.5,
                 safe_at = { 1610476, -436142 }, safe_km = 5.0, edge_km = 2.0,
                 -- ((2026-11-07) Alyssa's test: the Spear every 2-4 s) at most locks_per_player locks on a player at
                 -- a time (user: "Only two UAV's can lock onto a player at a time"), each lock_gap_s after the last
                 -- one on them (their strikes that far apart: 10, the user: "have the strikes come every 10 seconds
                 -- with the UAVs"), a UAV relock_s after its own strike
                 lock_after_s = 2.0, lock_delay_s = 1.5, lock_s = 8.0, relock_s = 1.0, imminent_s = 3.0,
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
    -- "escort" = THE ESCORT (Scripts/sv_escort.lua, tools/re/ESCORT.md; user, 2026-11-06): the allied B-1B CHARLENE
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
               -- the build's points (cm; tools/survival_events.py ESC_*, tools/re/ESCORT.md "Build names"): the approach
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
                 gun_accuracy_x = 20, gun_reach_x = 20, gun_life_x = 4,   -- ((0.73.76) its rounds' life x4, not x20)
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
    -- "fishing" = GONE FISHIN' (FISHING_ROUND_PLAN.md; tools/re/FISHING.md; Scripts/sv_fishing.lua): SAL, a Comona
    -- fisherman, needs fish for the island's festival and enlists the air force. Once a run (`once`), from from_round,
    -- in the random rotation; no enemies, nothing attacks the airfield. SAL and COMONA CONTROL talk it in on the
    -- subtitle strip (text.intro), then the shoals spawn and a time_s countdown runs (warnings at warn_s left). A shoal
    -- is a copy of the stock invisible turret pawn (DT_NPC row shoal_row on model row shoal_model, both added at the main
    -- menu); `units` hold 8 each, all round SAL's boat ((2026-11-07) user: "the shoals need to be more numerous and
    -- spread around the boat"; were three grounds of 8 far apart): the first on the boat (its shoals 300-800 m out),
    -- the others evenly on a ring of ring_m round it, turned at random each round (Scripts/sv_fishing.lua FISH.grounds;
    -- six units of the build: 48 shoals, about 0.3-2.7 km from the boat), each spawned shoal_z cm up (the sea's
    -- collision is at 3.5 m) with a hit sphere of sphere_m on collision profile sphere_profile (sphere = false: none).
    -- SAL's boat (boat_unit, an allied boat) at boat_at, boat_z, held at boat_min_health HP by its MinHealth field; a
    -- hit on it (this game's own copy) costs this game's player boat_penalty_kg (once every boat_hit_gap_s). A shoal's
    -- death plays `splash` (x splash_scale, The Big One x splash_big_x) at sea_z and draws the next catch of the round's
    -- one shuffled deck: `catch` the weights (apportioned to the shoals; The Big One at most bigone_max), `kg` each
    -- fish's range; credited to whoever destroyed it (co-op: the host's kill attribution, each player's own haul; the
    -- allies' catches shared out). The weigh-in: each player's kg x credits_per_kg + the grade's bonus (grade_s .. c
    -- the thresholds, kg; bonus_s .. d), + bigone_bonus with The Big One, x (1 + pay_per_round per round past
    -- from_round). In co-op each threshold is x players ^ -coop_grade_x (each player's share of the grounds). The card
    -- stays card_s; the round ends weigh_s after the time's up at most. check_s: how often the shoals are looked at;
    -- quiet_s: SAL's nudge after that long with no catch; empties_line: that many empties in a row draws his
    -- complaint. test_s: the test key's spawn is taken off that long after it.
    -- Pay (round 7, solo): an A (650-899 kg, ~770 with The Big One) about 6,000 Z, an S (~1,000 kg) about 9,000 Z.
    -- (48 shoals hold about 1,650 kg: an S takes about two thirds of them; every one about 12,000 Z.)
    fishing = { enabled = true, name = "GONE FISHIN'", from_round = 7, once = true,
                units = { "SV_Unit_FishA", "SV_Unit_FishB", "SV_Unit_FishC", "SV_Unit_FishD", "SV_Unit_FishE",
                          "SV_Unit_FishF" },
                ring_m = 1900,
                shoal_z = 700, sea_z = 350,
                shoal_row = "SV_Shoal", shoal_model = "SV_Model_Shoal", shoal_name_key = "SV_Shoal_Name", shoal_name = "SHOAL",
                shoal_sub_key = "SV_Shoal_Sub", shoal_sub = "",
                boat_unit = "SV_Unit_SalBoat", boat_at = { 1687842, -1191916 }, boat_z = 300, boat_yaw = 157, boat_min_health = 1.0,
                boat_name_key = "SV_SalBoat", boat_name = "SAL'S BOAT", boat_penalty_kg = 25, boat_hit_gap_s = 4,
                sphere = true, sphere_m = 8.0, sphere_profile = "EnemyPawn",
                splash = "/Game/VFX/Environment/Common/Explosion/GroundExplosion/groundExplosionA001/NS_groundExplosionASmallSea003",
                splash_scale = 1.0, splash_big_x = 2.5, test_s = 300,
                time_s = 180, warn_s = { 120, 60, 30, 10 }, check_s = 0.5, quiet_s = 30, empties_line = 3,
                catch = { none = 30, junk = 8, sardine = 22, mackerel = 18, tuna = 13, swordfish = 7, bigone = 2 },
                bigone_max = 1,
                kg = { sardine = { 15, 30 }, mackerel = { 25, 45 }, tuna = { 40, 90 }, swordfish = { 80, 140 },
                       bigone = { 250, 400 } },
                credits_per_kg = 6, pay_per_round = 0.04, bigone_bonus = 500, coop_grade_x = 1.0,
                grade_s = 900, grade_a = 650, grade_b = 400, grade_c = 150,
                bonus_s = 2500, bonus_a = 1000, bonus_b = 400, bonus_c = 100, bonus_d = 0,
                card_s = 14, weigh_s = 26,
                -- (what SAL and Comona's staff say: "S|" SAL, "C|" COMONA CONTROL, "T|" COMONA TOWER, "G|" the
                -- CREW CHIEF (2026-11-07, the user: "Give SAL and the Comona Airbase Staff some more unique lines");
                -- {kg}, {fish}, {grade}, {pay} filled in; one of each list at random, never the same twice running.
                -- intro, start, empties, cleared and weigh are said whole: a list of lines, or a list of such lists
                -- (one of them, never the same twice running); each of warn's a line or a list of lines. The HUD's
                -- texts after them.)
                text = { sal = "SAL", control = "COMONA CONTROL", tower = "COMONA TOWER", crew = "CREW CHIEF",
                         intro = { "C|All aircraft, we have an... unusual request on an open channel.",
                                   "S|Hello? Air force? It's Sal. The festival is in six days!",
                                   "S|The whole island comes to eat, and I have no fish. None!",
                                   "C|Sir, this is a military frequency.",
                                   "S|The fish are hiding. I marked them. You go boom, I collect.",
                                   "C|...Command approved it. For morale. You have three minutes.",
                                   "S|Three minutes! Go, go! The festival waits for no one!" },
                         start = { { "C|Shoals are on your HUD. The fishing grounds are hot.",
                                     "S|Every kilo feeds Comona. I pay in money. Also in soup." },
                                   { "C|Shoals marked. Weapons free on the... fish.",
                                     "S|Big ones pay the most. Small ones pay in soup." },
                                   { "T|Tower to all aircraft: the fishing grounds are open. Apparently.",
                                     "S|Go! The fish don't wait, and neither does my wife!" } },
                         none = { "S|Nothing! You blew up water. The festival can't eat water.",
                                  "S|Empty. The fish laugh at us now.",
                                  "S|That was a rock, I think. A dead rock now.",
                                  "S|My cousin swore the fish were there. My cousin lies.",
                                  "C|Confirmed kill on... the ocean.",
                                  "S|Water. Very well done water.",
                                  "T|Tower saw that splash from here. Nothing in it.",
                                  "S|You missed so hard the fish are clapping." },
                         junk = { "S|A boot! Only one. Who loses one boot?",
                                  "S|A shopping cart? Out here? Comona, what are you doing?",
                                  "S|My old net! Six years I look for that net.",
                                  "S|A tire. The festival can use it for the ring toss.",
                                  "S|A toilet seat. I don't want to know.",
                                  "S|A suitcase! Locked. The festival will open it.",
                                  "G|Crew Chief: that's our missing toolbox! We'll want that back.",
                                  "C|Control logs it as... debris. Sure." },
                         sardine = { "S|Sardines! Small, but many. Like my family.",
                                     "S|Little ones! Good for the festival grill.",
                                     "S|{kg} kilos of sardines. Already in a tin, almost.",
                                     "S|Sardines! My grandmother's recipe needs exactly this many.",
                                     "S|Small fish, big heart. Good work." },
                         mackerel = { "S|Mackerel! Now we are fishing!",
                                      "S|Beautiful mackerel. Pre-cooked, even. Thank you.",
                                      "S|{kg} kilos! My wife will stop asking where I was.",
                                      "S|Mackerel! The festival smells better already.",
                                      "G|Crew Chief: save us some of that mackerel, Sal." },
                         tuna = { "S|TUNA! Oh, you are good. You are very good.",
                                  "S|Yellowfin! I am crying a little. It's the salt.",
                                  "S|{kg} kilos of tuna! The festival will name a dish after you.",
                                  "C|Sir, please stop cheering on this frequency.",
                                  "S|Tuna! I owe you a drink. Maybe two.",
                                  "T|Tower here. Even we cheered for that one." },
                         swordfish = { "S|A swordfish! He wanted to fight. You won.",
                                       "S|Look at the size of him! The mayor will want a photo.",
                                       "S|Swordfish! He will be the centrepiece of the festival.",
                                       "S|Swordfish! He pointed at you first. A fair fight.",
                                       "C|Control confirms: one very angry swordfish, neutralised." },
                         bigone = { "S|THE BIG ONE. Forty years I chase him. FORTY YEARS.",
                                    "S|{kg} kilos! The whole festival eats from one fish!",
                                    "C|...Okay, that was impressive.",
                                    "S|I am going to cry. Don't look at me. Just fly.",
                                    "G|The whole hangar heard that. Everyone wants a photo." },
                         bigone_first = "S|...",
                         first = { "S|BOOM! Yes! That is how my grandfather fished. Smaller boom.",
                                   "S|First fish! My heart, my heart!",
                                   "S|We have fish! Mama, we have fish!" },
                         empties = { { "S|Maybe aim where the fish are? Just a suggestion.",
                                       "C|He has a point, and I hate that he has a point." },
                                     { "S|You are scaring them! Shhh. Quiet bombs.",
                                       "C|There's no such thing as a quiet bomb, Sal." },
                                     { "S|The fish are laughing again. I can hear them.",
                                       "T|Tower can hear them too, Sal." } },
                         gun = { "S|With the little gun! Like a spear fisherman. Respect.",
                                 "S|Bullets for fish! Very personal. I like it." },
                         ally = { "S|Your friend is good too! Tell him the fish are over there.",
                                  "S|Your friend there has a good eye! The fish fear you both." },
                         quiet = { "S|Hello? Are you fishing or sightseeing?",
                                   "S|The fish will not explode themselves, my friend.",
                                   "S|I hear engines. I do not hear fish exploding.",
                                   "C|Control to pilots: Sal is calling every ten seconds. Please fish." },
                         landed = { "S|You stop for coffee? The festival doesn't stop for coffee!",
                                    "G|Crew Chief: we'll turn you around fast. Sal won't stop calling.",
                                    "S|Why are you on the runway? The fish are in the water!" },
                         cleared = { { "S|You took all of them? The whole sea is at the festival now!",
                                       "C|Great. Now there's an environmental report to file." },
                                     { "S|Every shoal! The sea is empty! Is that bad? It's a festival!",
                                       "T|Tower is notifying the fisheries board." } },
                         boat = { "S|THAT IS MY BOAT!", "S|Not the boat! The boat is not a fish!",
                                  "S|Hey! I am IN this boat!", "S|My BOAT! I just painted her!",
                                  "S|Aim AWAY from the old man in the boat!" },
                         warn = { { "C|Two minutes left on the... fishing operation.",
                                    "T|Tower: two minutes. Sal's already sharpening his knives." },
                                  { "S|One minute! Hurry, the gulls are coming!",
                                    "S|One minute! My wife is watching from the dock!" },
                                  { "S|Thirty seconds! Anything that swims!",
                                    "S|Thirty seconds! Big ones, small ones, I don't care!" },
                                  { "C|Ten seconds. Wrap it up.", "T|Ten seconds, pilots. Then it's Sal's problem." } },
                         time_up = { "S|Stop, stop! My boat is full! Let me weigh!",
                                     "S|Enough! Enough! The boat is sinking with fish!" },
                         weigh = { { "S|Okay, okay. Let me see what the festival gets...",
                                     "S|{kg} kilos total. Hm. Hmm." },
                                   { "S|Into the scale. Careful, careful...",
                                     "S|{kg} kilos. Let me think about this." } },
                         grade_s = { "S|Legend of the sea! The festival will sing about you.",
                                     "S|The whole island eats tonight. Free fish for the pilots!",
                                     "S|I will tell my grandchildren about this. Twice." },
                         grade_a = { "S|A fine catch! Come to the festival. Front table.",
                                     "S|Good work. Not my grandfather's work, but good.",
                                     "S|Very good! The mayor will shake your hand. Wash it first." },
                         grade_b = { "S|Honest work. Honest fish. The festival will manage.",
                                     "S|Not bad. Not good. A Tuesday kind of catch.",
                                     "S|Enough for everyone. Small plates, but everyone." },
                         grade_c = { "S|Soup for the festival. Small soup.",
                                     "S|Well... the festival cats are happy.",
                                     "S|We will add a lot of potatoes." },
                         grade_d = { "S|The gulls eat better than this. Next time I call the navy.",
                                     "S|You blew up more water than fish. The festival weeps.",
                                     "S|I have seen more fish in my soup. And there's no fish in it." },
                         signoff = { "S|The money is in your accounts. Most of it.",
                                     "C|Fishing operation complete. Resume normal hostilities.",
                                     "S|See you at the festival! ...Hello? Hello?",
                                     "T|Tower: fishing operation closed. Sal, please get off this frequency.",
                                     "S|Thank you, pilots! I'm naming my next boat after you!",
                                     "G|Crew Chief: the hangar smells of fish now. Thanks, Sal." },
                         names = { none = "NOTHING", junk = "JUNK", sardine = "SARDINES", mackerel = "MACKEREL",
                                   tuna = "YELLOWFIN TUNA", swordfish = "SWORDFISH", bigone = "THE BIG ONE" },
                         catch_kg = "+%d KG %s", time_callout = "GONE FISHIN'", time_callout_sub = "%s ON THE CLOCK",
                         row_intro = "GONE FISHIN': SAL ON THE RADIO", row = "GONE FISHIN' %s  SHOALS %d  HAUL %d KG",
                         row_team = "  (TEAM %d)", row_weigh = "GONE FISHIN': THE WEIGH-IN",
                         card_title = "GONE FISHIN'  -  WEIGH-IN", card_hits = "SHOALS HIT  %d / %d      EMPTY  %d",
                         card_best = "BEST FISH  %s %d KG", card_best_none = "BEST FISH  NONE",
                         card_total = "TOTAL HAUL  %d KG      GRADE  %s", card_boat = "SAL'S BOAT  -%d KG",
                         card_pay = "PAYMENT  +%s Z", card_team = "TEAM HAUL  %s KG FROM %d PILOTS",
                         card_player = "%s  %d KG  %s" } },
    -- "festival" = THE FESTIVAL (FISHING_ROUND_PLAN.md 0; tools/re/FISHING.md 6; Scripts/sv_festival.lua): never drawn,
    -- it's round F + round_after of the day-night arc (F: GONE FISHIN''s round), at sunset, at the airfield. Lines
    -- thanking the pilots (text.talk), then the air raid siren loops at the airfield (`siren`, a Wwise event of the game's
    -- SE bank, siren_up_m over the runway, every game), the four searchlights (`lights`, allied; their rows ride in the
    -- Alicorn's tables: `rows`, lights_required true makes them the round's condition, else it goes without them) and
    -- three Tu-160 formations (SV_Unit_Fest<N|W|S>, ordered up_after_s after their spawn). Each launches salvo after
    -- salvo until it's shot down (2026-11-07, the user: "have the Bombers continually launching Cruise Missiles until
    -- the bombers are killed"): the first as it passes its launch point (launch_n / _w / _s, within launch_r_km of it;
    -- at the latest first_launch_<g> s after its spawn), then one every salvo_every_s (launch_gap_s apart at least; no
    -- unit free: again retry_s on): the next of its three missile units (SV_Unit_FestCM_<g><1-3>, never
    -- one whose last salvo isn't off the spawner's list: hard rule 16) at the launch point, launch_z up, flown to the
    -- runway (rwy, rwy_z) at 600 km/h. One within impact_m of the runway (flat) hits it (the host fires its impact
    -- record): impact_damage off the airfield, as a bomb; one up missile_s is taken off. A missile shot down pays
    -- pay_missile, a bomber pay_bomber (each x the round's kill multipliers). All 12 bombers down and nothing in the air:
    -- `reward` + reward_per_round x the round (a special's: split in co-op); time_limit_s: the raid's backstop.
    festival = { enabled = true, name = "THE FESTIVAL", round_after = 6,
                 rwy = { 1610476, -436142 }, rwy_z = 500,
                 launch_n = { 1610476, -2936142 }, launch_w = { -889524, -436142 }, launch_s = { 1610476, 2063858 },
                 launch_z = 200000, missiles = 4, impact_m = 400,
                 siren = "AKE_GEN_ENV_OBJ_AirRaid_Map17_Comona_Play", siren_s = 20, siren_up_m = 10,
                 test_s = 300,
                 lights = { "SV_Unit_FestLight_1", "SV_Unit_FestLight_2", "SV_Unit_FestLight_3", "SV_Unit_FestLight_4" },
                 rows = { "GR053_seli_01", "GR053_seli_light_01", "GR053_seli", "GR053_seli_light", "NWDID_GroundNPC" },
                 lights_required = false, up_after_s = 2, launch_r_km = 3.0, launch_gap_s = 30,
                 first_launch_n = 43, first_launch_w = 168, first_launch_s = 60, salvo_every_s = 30, retry_s = 5,
                 missile_s = 200, recycle_after_s = 3, impact_damage = 8,
                 pay_missile = 150, pay_bomber = 400, reward = 4000, reward_per_round = 150, time_limit_s = 900,
                 -- ((2026-11-07) the user: "Include more Enemy Aircraft in the Festival Mission and have the ending timer
                 -- for the next round last 60 seconds") fighters with the raid: fighters_share of the round's aircraft (whole
                 -- 2-ships, fighters_min .. fighters_max; 0: none); break_after_s: the break after its round (at least that,
                 -- the menu's BREAK BETWEEN ROUNDS if longer)
                 fighters_share = 0.7, fighters_min = 6, fighters_max = 16, break_after_s = 60,
                 -- ((2026-11-07) the user: "Add some Allied Target Boxes in the town next to the airfield", VALKA and
                 -- AUDREY side by side, "Concert" "Market Stall" "Food Truck" and the like) the town's boxes: the build's
                 -- unit of invisible, invincible allied dummies just past the runway's WSW end (tools/survival_events.py
                 -- FEST_TOWN_*), up with the festival (its talk), off at its end; their names text.town. chatter_s: a line
                 -- of text.chatter that often during the raid, when the strip has room
                 town = { enabled = true, unit = "SV_Unit_FestTown" }, chatter_s = 35,
                 -- (the lines: as GONE FISHIN''s, "S|" SAL, "C|" CONTROL, "T|" TOWER, "G|" the CREW CHIEF, and the
                 -- town's people by name ("VALKA|", "AUDREY|"; "MC|", "FOOD|", "MARKET|": CFG.hud.subs.speakers); talk,
                 -- all_down, timeout, raid_town and saved_town said whole: a list of lines or a list of such lists, one
                 -- of them; talk_nokg, launch, launch_again, shot_first, formation_down and chatter a line or a list of
                 -- lines, one of them; impact in turn. town: the boxes' names, by their callsign keys)
                 text = { sal = "SAL", control = "COMONA CONTROL", tower = "COMONA TOWER", crew = "CREW CHIEF",
                          town = { SV_FestBox_Concert = "CONCERT", SV_FestBox_Valka = "VALKA", SV_FestBox_Audrey = "AUDREY",
                                   SV_FestBox_Dance = "DANCE FLOOR", SV_FestBox_Market = "MARKET STALL",
                                   SV_FestBox_FoodTruck = "FOOD TRUCK", SV_FestBox_FishGrill = "SAL'S FISH GRILL",
                                   SV_FestBox_Dessert = "DESSERT TENT", SV_FestBox_Lanterns = "LANTERN STAND",
                                   SV_FestBox_RingToss = "RING TOSS", SV_FestBox_Soup = "SOUP KITCHEN",
                                   SV_FestBox_Fireworks = "FIREWORKS" },
                          talk = { { "C|All aircraft, the festival at Comona Airport has begun.",
                                     "S|Pilots! The whole island is here! Look at all this fish!",
                                     "S|{kg} kilos you caught for us. They named a soup after you.",
                                     "MC|Good evening, Comona! This first song is for the pilots up there!",
                                     "C|On behalf of the island: thank you, pilots.",
                                     "S|Come down! Eat! Dance! The sun is setting, it's perfect.",
                                     "C|...Wait. Radar contacts. North, west and south.",
                                     "C|Tu-160s! Air raid! All aircraft, defend the festival!" },
                                   { "T|Comona Tower to all aircraft: the festival is open. Enjoy the view.",
                                     "S|Pilots! Look down! Lanterns, music, and so much fish!",
                                     "S|{kg} kilos of your fish on the grills. The mayor cried.",
                                     "AUDREY|Valka, wave at the pilots. ...Properly, Valka. Thank you.",
                                     "G|Crew Chief: the hangar's full of tables. Sal's cousins are everywhere.",
                                     "S|At sunset we eat. At night we dance. Tomorrow we sleep!",
                                     "C|...Hold on. Multiple contacts. North, west and south.",
                                     "C|Tu-160s, inbound on the festival! All aircraft, engage!" } },
                          -- as the siren starts, in the town ((2026-11-07) the user: "Audrey is the Dominant one in the
                          -- relationship with Valka": AUDREY leads, VALKA follows. "Audrey is an Ex-grey man who worked
                          -- for Grunder Industries. Valka is Audreys girlfriend, Valka is a bit of an airhead but she's
                          -- extremely powerful because she's actually an Anomaly herself, she's what they call a Void
                          -- Watcher, she looks after all the dead who have passed on, however Valka resides on earth with
                          -- Audrey, the players will only be able to loosely connect the dots": hints only, never said)
                          raid_town = { { "VALKA|Audrey? Is that... an air raid siren? It's so loud.",
                                          "AUDREY|It is. Under the stage, Valka. Now. Don't argue." },
                                        { "MC|Folks, please remain calm! The band will keep playing!",
                                          "AUDREY|Valka, with me. Stay close and do exactly what I say." },
                                        { "FOOD|Everybody behind the trucks! Mind the grill!",
                                          "AUDREY|Valka. Hand. We're going behind the trucks." } },
                          -- now and then during the raid (chatter_s)
                          chatter = { "AUDREY|Nobody ruins my date night. Pilots, shoot them down!",
                                      "AUDREY|Valka, head down. I said down. Good girl.",
                                      "VALKA|Audrey says the pilots have this. Audrey is always right.",
                                      "VALKA|Audrey, you're squeezing my hand. ...No, keep squeezing.",
                                      "AUDREY|Stop looking at the bombers, Valka. Look at me. Better.",
                                      "AUDREY|Tu-160s. I used to read their maintenance logs. Long story.",
                                      "AUDREY|Grunder built the guidance in those missiles. I'd know.",
                                      "AUDREY|Old habit: I count exits. There are four. We're fine.",
                                      "AUDREY|The old men in grey would've loved this raid. I don't miss them.",
                                      "AUDREY|Valka, you're doing the staring thing again. Stop it. People notice.",
                                      "VALKA|Don't worry about the bomber crews. I'll look after them now.",
                                      "VALKA|I'm not scared. Nobody's ever really gone, you know?",
                                      "VALKA|Audrey, the sky's very crowded tonight. With people, I mean.",
                                      "VALKA|The radar plane's called Void Watcher? Cute. Very cute.",
                                      -- ((2026-11-07) the user: "Valka is prone to being captured and sometimes she has
                                      -- outbursts where she becomes the full anomaly version of herself (the X-02S
                                      -- anomaly). Her sister is a girl named War, who they all believe is evil, because
                                      -- she actually is evil": hints only)
                                      "AUDREY|Valka, stay where I can see you. I'm not finding you in a lab again.",
                                      "VALKA|My head's buzzing, Audrey. Like the last time.",
                                      "AUDREY|Breathe, Valka. Not here. Not tonight. Squeeze my hand.",
                                      "AUDREY|If you feel it coming, you tell me. No flying off this time.",
                                      "VALKA|War would've loved this raid. ...Don't tell her I said that.",
                                      "AUDREY|We don't talk about your sister, Valka. Not tonight.",
                                      "MC|This next song is called Please Shoot Down The Missiles!",
                                      "MC|Comona, give it up for the pilots! Louder than the siren!",
                                      "FOOD|Free tacos for whoever gets a bomber!",
                                      "FOOD|I'm not leaving my truck. The grill is still on!",
                                      "MARKET|My lanterns! Careful with my lanterns!",
                                      "MARKET|Everything half price if the stall survives!",
                                      "S|My fish grill is still standing! Keep it that way!",
                                      "G|Crew Chief: we've got the kids in the hangar. Keep shooting!" },
                          -- ((2026-11-07) the user: "add other Characters like Yorke, Rock, Ali, Danielle into this as
                          -- well. Yorke is the Team Leader of their Squadron, Rock is his 2nd in command, Ali and Danielle
                          -- are dating") KMG at the festival, only once CHARLENE has landed at Comona this run (THE
                          -- ESCORT: RUN.escort.arrived), never one shot down in it: kmg_talk after the talk, kmg_raid as
                          -- the siren starts, kmg_chatter among the chatter, kmg_saved after saved_town
                          kmg_talk = { { "CHARLENE|Comona, Kokoda thanks you for your hospitality. The fish is divine.",
                                         "YORKE|KMG's on the ground and off duty. Mostly.",
                                         "ROCK|Mostly." },
                                       { "CHARLENE|I've been to festivals in Aurelia. None with this much fish.",
                                         "DANIELLE|Ali, they have a dance floor. You're dancing.",
                                         "ALI|...I'm dancing." } },
                          kmg_raid = { { "YORKE|KMG, we're grounded. Get the civilians to the hangars. Move.",
                                         "ROCK|On it, lead." },
                                       { "CHARLENE|My Lancer is parked forty metres from that runway. Shoot them down!",
                                         "YORKE|You heard her, pilots." },
                                       { "DANIELLE|Ali, our first night off in a month. Of course.",
                                         "ALI|Stay close. ...Closer. Okay, that's close." } },
                          kmg_chatter = { "YORKE|KMG, keep the crowd moving. Calm and quick.",
                                          "ROCK|Hangar's full. Sending the rest behind the trucks.",
                                          "ROCK|Lead, the kids are in the hangar. All of them.",
                                          "ALI|Danielle, stay behind me. ...Fine, I'll stay behind you.",
                                          "DANIELLE|Ali, if a missile ruins this date I'm shooting it myself.",
                                          "CHARLENE|Someone tell those bombers my collection isn't insured tonight.",
                                          "CHARLENE|Pilots, the Kokoda Mercenary Group is watching. Impress us." },
                          kmg_saved = { { "YORKE|Good work, pilots. KMG owes Comona a round of drinks.",
                                          "ROCK|Two rounds." },
                                        { "DANIELLE|Ali. The band's back. You promised me a dance.",
                                          "ALI|I did. Lead the way." },
                                        { "CHARLENE|Splendid. Now, where was I? Ah, yes. The fish." } },
                          -- after all_down, in the town
                          saved_town = { { "AUDREY|There. I told you they'd get them. Now, Valka: dance with me.",
                                           "VALKA|...Yes, Audrey." },
                                         { "MC|Comona, the pilots saved the festival! Hit it, band!",
                                           "AUDREY|Valka. Dance floor. Now.",
                                           "VALKA|Coming, Audrey! ...Bye, bomber people. Rest well." },
                                         { "VALKA|Audrey? You can let go of my hand now.",
                                           "AUDREY|No. I don't think I will." },
                                         { "VALKA|All those crews... I'll go visit them later. They seem lonely.",
                                           "AUDREY|Not tonight, Valka. Tonight you're mine." },
                                         { "VALKA|See? I stayed me the whole time, Audrey.",
                                           "AUDREY|You did. I'm proud of you." } },
                          talk_nokg = { "S|Every kilo you caught is on a plate tonight.",
                                        "S|Every fish you caught is on a grill tonight." },
                          launch = { "C|Missile launch from the {dir}! Cruise missiles inbound!",
                                     "T|Tower: launches from the {dir}! Everybody off the runway!",
                                     "S|Something is flying at us from the {dir}! Fireworks?!" },
                          launch_again = { "C|Another salvo from the {dir}!",
                                           "C|They're launching again, {dir}!",
                                           "G|More from the {dir}! Get the crowd into the hangars!" },
                          shot_first = { "S|You shot it! The grill is safe!",
                                         "S|Boom in the sky, not on my tent! Good!" },
                          impact = { "C|Impact on the airfield!", "S|My table! They hit my table!",
                                     "S|Not the dessert tent!", "G|Crater on the apron! Crews, move!",
                                     "S|The fish! Somebody save the fish!", "T|Tower's shaking! We're still here!" },
                          formation_down = { "C|The {dir} formation is down.",
                                             "T|Tower confirms: the {dir} bombers are gone!",
                                             "S|The {dir} ones fell! The crowd is cheering!" },
                          all_down = { { "C|All bombers down. The skies are clear.", "S|The festival goes on! Music! MUSIC!" },
                                       { "C|Last bomber down. Comona is clear.",
                                         "S|Dance! Everybody dance! The pilots saved the soup!",
                                         "G|Crew Chief: drinks at the hangar. Pilots first." } },
                          timeout = { { "C|The bombers are turning for home. Let them go." },
                                      { "C|The raid's breaking off. Hold your fire.",
                                        "S|They run! Go home, and tell your friends about our fish!" } },
                          dirs = { N = "north", W = "west", S = "south" },
                          raid_go = "AIR RAID", raid_go_sub = "TU-160S FROM THE NORTH, WEST AND SOUTH",
                          launch_callout = "CRUISE MISSILES", launch_callout_sub = "FROM THE %s: SHOOT THEM DOWN",
                          saved = "THE FESTIVAL IS SAVED", saved_sub = "+%d ZOLLARS", over = "THE RAID IS OVER",
                          row_talk = "THE FESTIVAL", row = "THE FESTIVAL  BOMBERS: %d  MISSILES IN THE AIR: %d" } },
    -- TEST ONLY BEGIN (the lightning Anomaly and the storm test: test builds only, tools/re/THUNDER.md)
    -- "thunder" = IFF FATAL ERROR / DI..ANT TH..D..R (user, 2026-11-06: "another Anomaly, one that uses Lightning Against
    -- you", "The Aircraft is an A-10", "Strikes should only black out and disorient you", "it can only be spawned with
    -- the test key"): never in `rotation`; Ctrl+. (period) makes the next round its (sv_anomalies.lua THUNDER). Its A-10 flies
    -- the plain campaign row `row` on MINDRIPPER's unit `unit` (SV_SetAircraft, as MINDRIPPER's F-4E: that unit's stock
    -- records give it MINDRIPPER's orders, MISSION UPDATE beep, forced WARNING and crackle; no build data), spawn_km
    -- from you, at AI level ai_level, health HP x (1 + health_per_round a round after specials.first, at most
    -- health_max_x); `reward` (+ reward_per_round a round) when it's down. Its box's callsign line: name (on name_key,
    -- the plane's CallsignId); its round's callout and warning (text.warn): tag, with start_sound (a Wwise event of the
    -- game's SE bank; stop_sound at its end), and the focus camera `camera` ("": none). Its storm (`storm`): the stock
    -- lightning volume (storm.class, Missions 12 and 16's) kept on it, radius_m round it; its strikes are the stock
    -- ones (the HUD hidden 2 s, electronic noise 6-10 s, a camera shake, the engine's stall flag; never damage, and only
    -- player planes), min / max_interval_s between its rolls (0: the volume's own 3-5 s), curve the strike chance curve
    -- (the game's CUR_LightningWeight row; "": the volume's own); log_strikes: each strike Lua sees, logged. `fx`: the
    -- game's cloud lightning crackling on it every every_s. `test`: the storm test's (Ctrl+, comma) radius on you, its time
    -- and its second press's LS_StallTime (the stall flag's length on your plane; stock 0.7 s).
    -- ((2026-11-07) it waits for CHARLENE as the Anomalies do (CFG.specials.anomaly_gate), and she warns of it the round
    -- before: wait_for_charlene, charlene_warn (her lines, as CFG.specials.escort.text.say.warn_<kind>'s); the gate never
    -- holds a test key's forced round, and this one comes only by its key)
    thunder  = { enabled = true, name = "DI..ANT TH..D..R", tag = "IFF FATAL ERROR", unit = "SV_Unit_Anomaly",
                 wait_for_charlene = true,
                 charlene_warn = { { "CHARLENE|Pilots, Charlene. An Anomaly is approaching, with a storm.",
                                     "CHARLENE|Lightning, next round. It'll blind you. Keep flying." },
                                   { "CHARLENE|There's a storm on my scope that isn't weather. An Anomaly.",
                                     "CHARLENE|It arrives next round. Watch the sky." } },
                 row = "a10c_common", name_key = "SV_Thunder_Name",
                 health = 1000, health_per_round = 0.05, health_max_x = 2.5, reward = 8000, reward_per_round = 300,
                 ai_level = 5, spawn_km = { 8, 12 }, camera = "LookAt_Event_Camera_ms22-01",
                 start_sound = "AKE_GEN_ENV_AMB_ThunderCloud_Outside_DistantThunder_Play",
                 stop_sound = "AKE_GEN_ENV_AMB_ThunderCloud_Outside_DistantThunder_Stop",
                 storm = { radius_m = 3000, min_interval_s = 0, max_interval_s = 0, curve = "MS_12", log_strikes = true,
                           class = "/Game/Blueprints/System/Lightning/BP_LightninigVolume_MS12.BP_LightninigVolume_MS12_C",
                           curve_table = "/Game/Blueprints/System/Lightning/CUR_LightningWeight.CUR_LightningWeight" },
                 fx = { enabled = true, every_s = 2.5, scale = 4.0, life_s = 3.0,
                        system = "/Game/VFX/Environment/Common/Lightning/CloudLightning/NS_CloudLightning" },
                 test = { radius_m = 3000, seconds = 60, stall_s = 3.0 },
                 text = { warn = "WARNING: %s", warn_sub = "%s: ITS STORM BLINDS YOU", down = "%s DOWN",
                          down_sub = "+%d ZOLLARS", row = "%s: %.1f KM", row_storm = "%s: IN ITS STORM",
                          key = "TEST: %s", key_now = "STARTING NOW", key_next = "NEXT ROUND",
                          storm_on = "TEST: STORM ON YOU", storm_on_sub = "%d S, %.1f KM", storm_stall = "TEST: STALL %.1f S",
                          storm_stall_sub = "LS_STALLTIME ON YOUR PLANE", storm_off = "TEST: STORM OFF" } },
    -- TEST ONLY END
}
-- The sky (Scripts/sv_sky.lua; tools/re/FISHING.md 5): the day-night arc's owner. It never writes the stock sky asset
-- (Mission 4's CSP_ms04...), only the renderer's working copies of its params, the sun light, the sky light, the
-- post-process volumes' exposure, two material parameter collections (mpc_env, mpc_vfx) and Cloudly's custom sun, each
-- value's original kept and put back (at a run's end; a level torn down drops them).
-- readback_s: the test key's (Ctrl+F6) read-back after each step. test_sun: step 2's custom sun (elevation, azimuth: a
-- compass bearing, east 90); test_copies: step 3's, through the copies and the light alone; night: the night's sky (the
-- arc's round F+7, the test's step 4; the stock night's way, Mission 9's: the light at the moon's spot, dim and bluish,
-- a moon-sized sun disc, the moon on, its exposure (min, max, bias), the sky light x skylight_x and blue, the city's glow
-- (emissive) up, the effects' EV down), with the stars at the stock maximum (stars: Mission 22's dawn).
-- arc: the day-night arc GONE FISHIN' starts (FISHING_ROUND_PLAN.md 0; F its round): the sun sinks a step a round over
-- F+1 .. F+5 (sink_el / sink_az, exposure to dusk_exposure), sets at F+6 (sunset: from sunset_el to set_el, sky light x
-- sunset_skylight, city glow sunset_emissive, effects' EV sunset_vfx_ev, sunset_exposure), night from F+7 (`night`) for
-- night_rounds rounds (3: the user, 2026-11-07), then
-- rises in the east over sunrise_rounds rounds from dawn (dawn_el / dawn_az, dawn_exposure, dawn_skylight,
-- dawn_emissive, dawn_vfx_ev) to midday (midday_el / midday_az, day_exposure), held for the rest of the run. Each round
-- drifts toward the next round's sky (within_x of the step over round_s of the fight; swap_within_x for a step that
-- swaps the sun for the moon, so the swap is at the break's darkest point: the light at dark_factor), finished in the
-- break; brightness (the light's factor, the city's glow) in log space. apply_s: how often it's written (the MPCs every
-- tick); blend_s: a late joiner's (or a new level's) blend in. path: "asset" (the level's sky asset, which Cloudly
-- draws the sky and its sun light from: the user's sky test of 2026-11-07, after a run where the sun "isn't moving at
-- all" and the night "looks over exposed"), "copies" (the renderer's copies + the light: undone every frame) or
-- "custom" (Cloudly's custom sun API as well). stock: Mission 4's sky, when the level's can't be read; stock.asset:
-- the sky asset's values as shipped (CSP_ms04_20251218b, read in game 2026-11-07), put back when a run finds them
-- changed (an earlier run or test left them so).
-- valka_gate: VALKA doesn't come from GONE FISHIN' to the arc's midday (the user, 2026-11-06).
-- ((2026-11-07, 0.74.10) the user's screenshots of round F+7: the ground and the planes white and noisy under a black
-- sky, "everything was working perfectly though until the sun disappeared": Mission 9's night exposure (min 0.5) let
-- the camera brighten the scene ~5,000 times, lit by the day's sky light x0.1, and its city glow x10,000 blew out
-- what has any glow. Night and dawn now take the sunset's way, which looked right: the exposure held near the day's
-- (night 10.5 / 14 / -1.5, dawn 10 / 14 / -1), the glow 100, the effects' EV 7 / 8.)
-- ((2026-11-07, 0.74.10) the user: "the sun does not seem to be setting, it seems to be just moving to the right
-- constantly instead of going down": the old path swept 142 -> -105 (113 deg round the sky) while it sank 18 deg, 6 deg
-- down for 60 sideways by F+3) The sun sinks where it is: the stock sun's bearing (142) drifting 18 deg as it sets,
-- a real sunset's slant; it rises in the east after the night as before.
CFG.sky = { enabled = true, readback_s = 5,
            mpc_env = "/Game/Base/Material/MPC/MPC_Env_Control.MPC_Env_Control",
            mpc_vfx = "/Game/Base/Material/MPC/MPC_VFX_Control.MPC_VFX_Control",
            test_sun = { -2.0, -105.0 }, test_copies = { 4.0, -120.0 },
            night = { sun_el = 35.0, sun_az = -130.0, factor = 0.5, rgb = { 0.89, 0.96, 1.0 }, sun_disc = 0.57,
                      moon_el = 35.0, moon_az = -130.0, exposure = { 10.5, 14.0, -1.5 },
                      skylight_x = 0.1, skylight_rgb = { 0.55, 0.65, 1.0 }, emissive = 100.0, vfx_ev = 7.0 },
            stars = { intensity = 7.0, background = 22.0, radius = 2.5, fraction = 0.73, rotation = { 2.578, 0.0, 0.0 },
                      mask_start = 0.263 },
            arc = { enabled = true, path = "asset", apply_s = 2.0, blend_s = 5.0, round_s = 240, within_x = 0.75,
                    swap_within_x = 0.45, dark_factor = 0.25, night_rounds = 3, sunrise_rounds = 4, sunrise_light_x = 2, valka_gate = true,
                    sink_el = { 12.5, 10.0, 7.5, 5.0, 3.0 }, sink_az = { 145.0, 148.0, 151.0, 154.0, 157.0 },
                    dusk_exposure = { 11.0, 14.0, -0.5 },
                    sunset_el = 1.0, set_el = -3.0, sunset_az = 160.0, sunset_exposure = { 9.5, 14.0, -1.0 },
                    sunset_skylight = 0.5, sunset_emissive = 100.0, sunset_vfx_ev = 8.0,
                    dawn_el = -4.0, dawn_az = 105.0, dawn_exposure = { 10.0, 14.0, -1.0 }, dawn_skylight = 0.3,
                    dawn_emissive = 100.0, dawn_vfx_ev = 8.0,
                    midday_el = 52.9, midday_az = 180.0, day_exposure = { 13.0, 14.0, 0.0 },
                    stock = { el = 15.0, az = 142.0, factor = 120000.0, emissive = 1.0, vfx_ev = 11.0, disc = 1.2783,
                              exposure = { 13.0, 14.0, 0.0 },
                              asset = { sun_el = 15.0, sun_az = 142.0, sun_factor = 120000.0, sun_r = 1.0, sun_g = 1.0,
                                        sun_b = 1.0, sun_disc = 1.2783, unreal_sun = false, moon_on = false, moon_el = 10.0,
                                        moon_az = 135.0, moon_phase = 0.15, moon_phase_angle = 0.0, moon_disc = 0.5683,
                                        moon_bright = -4.0, moon_frac = 2.5e-06, stars_on = true, stars_int = 4.0,
                                        stars_bg = 0.0, stars_radius = 2.0, stars_frac = 0.5, stars_rx = 0.0, stars_ry = 0.0,
                                        stars_rz = 0.0, stars_mask = 0.05 } } } }
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
CFG.music = {
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
}
-- Round HUD. Positions are on the game's HUD design canvas (3840x2160, scaled to the screen; tools/re/HUD_LAYOUT.md).
CFG.hud = {
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
    -- (0.74.0) the subtitle strip (Scripts/sv_subs.lua SUB.say: GONE FISHIN', THE FESTIVAL): a panel w x h at y (its
    -- top, centred; clear of the minimap and the plane's panel), the speaker's name (colors by name, else color) over
    -- the line in text_color, each line line_s on screen unless said otherwise, at most max_queue waiting; blip: a Wwise
    -- event of the game's SE bank played as each line comes up ("": none). Shown only while a line is up.
    -- ((2026-11-07) the text wrapped at the box's width less 80; its lines counted by width (the font's em
    -- em_units design units: the user's screenshots read 48-50) to grow the box line_h a line)
    subs             = { enabled = true, y = 1700, w = 1560, h = 150, speaker_dy = 12, text_dy = 58, line_s = 4.0,
                         em_units = 50, line_h = 68,
                         max_queue = 16, fill = { 0.02, 0.10, 0.04, 0.70 }, edge = { 0.6, 1.0, 0.65 }, edge_px = 3,
                         color = { 0.26, 1.0, 0.33 }, text_color = { 1.0, 1.0, 1.0 }, blip = "",
                         -- (2026-11-07: Comona's tower and crew chief, CHARLENE and her four KMG escorts too)
                         colors = { SAL = { 1.0, 0.78, 0.32 }, ["COMONA CONTROL"] = { 0.45, 0.85, 1.0 },
                                    ["COMONA TOWER"] = { 0.62, 0.70, 1.0 }, ["CREW CHIEF"] = { 0.82, 0.82, 0.70 },
                                    CHARLENE = { 1.0, 0.52, 0.76 }, YORKE = { 1.0, 0.42, 0.36 },
                                    ROCK = { 0.86, 0.62, 0.42 }, ALI = { 0.76, 0.56, 1.0 },
                                    DANIELLE = { 1.0, 0.95, 0.48 },
                                    -- (THE FESTIVAL's town, 2026-11-07)
                                    VALKA = { 0.55, 0.80, 1.0 }, AUDREY = { 1.0, 0.68, 0.86 },
                                    ["CONCERT MC"] = { 0.98, 0.58, 0.30 }, ["FOOD TRUCK"] = { 0.70, 0.95, 0.50 },
                                    ["MARKET STALL"] = { 0.90, 0.80, 0.60 } },
                         -- a line's speaker code ("MC|...") to the name on the strip; a code not here is the name
                         speakers = { MC = "CONCERT MC", FOOD = "FOOD TRUCK", MARKET = "MARKET STALL" } },
    -- (0.74.0) the results card (SUB.card: GONE FISHIN''s weigh-in): w wide from y, a title and `rows` lines (top: the
    -- first line's offset; bottom: the space under the last), on the summary's fill and edge
    card             = { y = 270, w = 1500, rows = 10, top = 110, bottom = 40 },
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
    -- (0.73.80, findings perf4 / specials8 of 2026-11-04) the airfield's landing menu (the STORE's pages): its windows
    -- are kept once found (sv_core.lua landingWindows) and every object walked for them again only on landing, when a
    -- page closes, after a STORE press on a page not found yet, every every_s while none is on screen (the menu not up
    -- yet) and every backstop_s while one is (0: never). Lower finds the menu sooner as it opens (its row icons, co-op's
    -- music hold); each walk is a 25-40 ms hitch late in a run. Each game's own (hud: never synced).
    landing          = { every_s = 2.0, backstop_s = 30.0 },
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
        aces_break   = "%s BREAKS OFF",                -- ((0.73.78) CFG.aces.break_off: the squadron's name)
        aces_break_sub = "%d OF THEM LEAVING",
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
        -- ((0.73.78, plan G6) a call refused: the round's airstrike used; only an ace squadron's flights near)
        airstrike_once_sub = "ONE A ROUND: THE NEXT IN ROUND %d",
        airstrike_aces_sub = "NEVER ON AN ACE SQUADRON",
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
        lb_coop_host = "CO-OP: THE HOST SENDS THE RUN",   -- ((0.73.77) a co-op joiner's summary: LB.send)

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
        spaceport_sub = "ENEMY FLEET WEST OF THE SPACEPORT",
        fishing_sub  = "SAL NEEDS FISH FOR THE FESTIVAL",          -- (0.74.0: GONE FISHIN', sv_fishing.lua)
        festival_sub = "COMONA CELEBRATES AT SUNSET",              -- (0.74.0: THE FESTIVAL, sv_festival.lua)
        retake_sub   = "RETAKE THE SPACEPORT",
        sp_go        = "SPACEPORT ASSAULT",
        sp_go_sub    = "SINK THE FLEET BEFORE ITS TROOPS TAKE THE SPACEPORT",
        sp_row       = "FLEET: %d SHIPS  LANDING CRAFT: %d  SPACEPORT CAPTURE: %d%%",
        sp_row_tu160 = "  TU-160S: %d",
        sp_tu160     = "TU-160S INBOUND",
        sp_tu160_sub = "FROM THE %s: PROTECT THE AIRFIELD",
        sp_landing   = "LANDING CRAFT LAUNCHED",
        sp_landing_sub = "THE WASPS ARE SENDING THEM IN",
        sp_ashore    = "TROOPS ASHORE",
        sp_ashore_sub = "THEY CAN'T BE STOPPED ASHORE: SINK THE WASPS",
        sp_troops_in = "TROOPS AT THE SPACEPORT",
        sp_troops_in_sub = "SPACEPORT %d%% CAPTURED",
        sp_wasp_down = "WASP SUNK",
        sp_wasp_down_sub = "NO MORE LANDINGS FROM IT",
        sp_ford_down = "CARRIER SUNK",
        sp_ford_down_sub = "NO MORE FIGHTERS OFF ITS DECK",
        sp_captured  = "SPACEPORT CAPTURED",
        sp_captured_sub = "RETAKE IT NEXT ROUND",
        sp_lost      = "SPACEPORT LOST",
        sp_lost_sub  = "%d SHIPS STAY OFFSHORE FOR THE RETAKE",
        sp_held      = "SPACEPORT HELD",
        sp_held_sub  = "+%d ZOLLARS",
        sp_retake_go = "SPACEPORT RETAKE",
        sp_retake_go_sub = "DESTROY THE GARRISON, THE ISLAND'S DEFENCES AND THE ROCKETS",
        sp_retake_row = "GARRISON: %d  FLEET: %d SHIPS",
        sp_rocket_launch = "ROCKET LAUNCH",
        sp_rocket_launch_sub = "SHOOT IT DOWN BEFORE IT REACHES ORBIT",
        sp_rocket_down = "ROCKET DOWN",
        sp_rocket_down_sub = "+%d ZOLLARS",
        sp_rocket_escaped = "ROCKET ESCAPED",
        sp_rocket_escaped_sub = "-%d ZOLLARS, NO RETAKE BONUS",
        sp_debris    = "THE ROCKET BREAKS UP",
        sp_debris_sub = "DESTROY ITS FALLING DEBRIS",
        sp_debris_down = "DEBRIS DESTROYED",
        sp_debris_down_sub = "THE ROCKET IS GONE",
        sp_retaken   = "SPACEPORT RETAKEN",
        sp_retaken_sub = "+%d ZOLLARS",
        shop_captured = "SHOP CLOSED: THE AIRFIELD IS CAPTURED.",
        -- THE DECOY, named "Shoot Down The RECON Drone" (the user, 2026-11-07; sv_decoy.lua: its round's callout, its
        -- NEXT row, its bait and trap)
        dc_sub       = "RECON DRONE IN THE FAR NORTH",
        dc_go        = "SHOOT DOWN THE RECON DRONE",
        dc_go_sub    = "IT'S MARKING THE AIRFIELD FROM THE FAR NORTH",
        dc_row_bait  = "RECON DRONE: %.1f KM",
        dc_row       = "SPEAR UAVS: %d UP  %d DOWN  %d TO COME",
        dc_bait_down = "RECON DRONE DOWN",
        dc_bait_down_sub = "+%d ZOLLARS",
        dc_trap      = "IT WAS A TRAP",
        dc_trap_sub  = "SPEAR UAVS: SHOOT DOWN EACH ONE THAT LOCKS YOU",
        dc_done      = "THE TRAP IS BROKEN",
        dc_done_safe = "SAFE AT THE AIRFIELD",
        dc_done_time = "THE SPEAR UAVS WITHDRAW",
        dc_done_sub  = "+%d ZOLLARS",
        ace_sub      = "%s SQUADRON (%s)",
    },
}
