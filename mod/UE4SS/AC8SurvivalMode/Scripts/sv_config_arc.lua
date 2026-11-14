-- sv_config_arc.lua: CFG.specials' last fields, each a statement of its own from `CFG.specials = {`
-- (sv_config_specials.lua): GONE FISHIN' and THE FESTIVAL (CFG.specials.fishing, festival and the rest); CFG.sky (the
-- sky and the day-night arc), CFG.music and CFG.hud (the HUD and its texts). Piece 3 of 5 of sv_config.lua's family
-- (sv_config.lua, sv_config_specials.lua, sv_config_arc.lua, sv_config_subs.lua, sv_config_ini.lua), split from
-- sv_config_specials.lua by tools/lua_split_part.py and run by main.lua right after the piece before it: a name another
-- part uses is a global of this mod's Lua state, its own helpers stay local.
-- "fishing" = GONE FISHIN' (FISHING_ROUND_PLAN.md; docs/re/FISHING.md; Scripts/sv_fishing.lua): SAL, a Comona
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
CFG.specials.fishing = { enabled = true, name = "GONE FISHIN'", from_round = 7, once = true,
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
                         card_player = "%s  %d KG  %s" } }
-- "festival" = THE FESTIVAL (FISHING_ROUND_PLAN.md 0; docs/re/FISHING.md 6; Scripts/sv_festival.lua): never drawn,
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
CFG.specials.festival = { enabled = true, name = "THE FESTIVAL", round_after = 6,
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
                 -- ((2026-11-08) the user: "the Enemy Aircraft that spawn in during the Festival Special Round, they need
                 -- to spawn WITH the TU-160's not beforehand, and the Festival isn't saved until all Enemy Aircraft are
                 -- dealt with"; "Dialogue from Fesitival Round can run till the end of the 60 second timer") its fighters
                 -- held through its talk (at most hold_max_s), coming with the raid; saved only once its bombers, their
                 -- missiles and every enemy aircraft of the round are down (saved_needs_fighters; text.bombers_down when
                 -- only fighters are left); the town talking on through the break (break_chatter: text.after_chatter,
                 -- KMG's kmg_after, a line every break_chatter_s, the last one done before the next round)
                 hold_max_s = 180, saved_needs_fighters = true, break_chatter = true, break_chatter_s = 10,
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
                          row_talk = "THE FESTIVAL", row = "THE FESTIVAL  BOMBERS: %d  FIGHTERS: %d  MISSILES IN THE AIR: %d",
                          bombers_down = "THE BOMBERS ARE DOWN", bombers_down_sub = "SHOOT DOWN THE LAST %d FIGHTERS",
                          -- ((2026-11-08) the town after its raid, through the break: one line at a time, none twice)
                          after_chatter = { "MC|The band is back on! Give it up for the pilots!",
                                            "FOOD|Grill's back on. First skewer's free for a flight suit.",
                                            "MARKET|One lantern broken. I'll call that a good night.",
                                            "S|I counted the fish twice. All there! The feast goes on!",
                                            "T|Tower: runway's clear of debris. Thank you, all of you.",
                                            "G|Crew Chief: refuel, rearm, then go eat. That's an order.",
                                            "C|Comona Control: radar's quiet. Enjoy the festival.",
                                            "AUDREY|Valka, the music's back. You promised me a dance.",
                                            "VALKA|Audrey, the lanterns look like little missiles. Pretty ones.",
                                            "AUDREY|Don't stare at the sky, Valka. Look at me. There you go.",
                                            "VALKA|Can I have a skewer? And another skewer? Audrey, can I?",
                                            "AUDREY|One skewer. Then we sit where I can see the exits.",
                                            "VALKA|My head's quiet again, Audrey. I like it quiet.",
                                            "AUDREY|Good. Keep it that way. Hold my hand and breathe." },
                          kmg_after = { "YORKE|KMG, stand down. Enjoy the festival, you earned it.",
                                        "ALI|First time I've seen Comona dance. I could get used to it.",
                                        "DANIELLE|Somebody save me a seat by the stage. I'm landing hungry.",
                                        "ROCK|Tell the band to play something loud. We're coming in." } } }
-- TEST ONLY BEGIN (the lightning Anomaly and the storm test: test builds only, docs/re/THUNDER.md)
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
CFG.specials.thunder  = { enabled = true, name = "DI..ANT TH..D..R", tag = "IFF FATAL ERROR", unit = "SV_Unit_Anomaly",
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
                 -- ((2026-11-08) `strike`: Survival's own strikes on you inside its storm (sv_anomalies_dev.lua: the stock
                 -- volume never struck in the user's test of 0.74.34; stock = true spawns it too): a roll every roll_s
                 -- (a random time between the two, game time), chance[k] for the k-th roll since the last strike; a
                 -- strike: the HUD out blackout_s, static_s of noise with the HUD's distortion (min, max), damage_pct of
                 -- your MaxHealth (can_kill: a lethal one is your death), your controls upset upset_s (roll inverted,
                 -- throttle and brake swapped: upset_roll / upset_throttle), the camera shake x shake_scale, the
                 -- discharge on your plane; a miss: the evasion bolt miss_ahead_m ahead and the sparks on you)
                 strike = { enabled = true, stock = false, roll_s = { 1.5, 2.5 }, chance = { 0.35, 0.5, 0.65, 0.8 },
                            damage_pct = 10, can_kill = true, blackout_s = 3.5, static_s = { 10, 16 }, distortion = { 0.3, 1.0 },
                            upset_s = 1.5, upset_roll = true, upset_throttle = true, upset_fade_s = 0.2, shake_scale = 1.5,
                            near_miss_fx = true, miss_ahead_m = { 400, 550 },
                            shake = "/Game/Blueprints/Vehicle/PLAYER/Camera/CameraShake/BP_CamShake_Lightning",
                            fx_strike = "/Game/VFX/Vehicles/Aircraft/Common/ElectricDischarge/NS_ElectricDischargeM001",
                            fx_miss = "/Game/VFX/Vehicles/Aircraft/Common/ElectricDischarge/NS_ElectricEvasion001",
                            fx_sign = "/Game/VFX/Vehicles/Aircraft/Common/ElectricDischarge/NS_ElectricSign001",
                            sound_strike = "AKE_GEN_PLAYER_EXP_Damaged_StruckByThunder_Play",
                            sound_damage = "AKE_Player_Damage_Lightning_Play",
                            sound_roll = "AKE_GEN_ENV_AMB_ThunderCloud_Inside_Lightning_Play",
                            sound_noise = "AKE_Ms12_UI_HUD_Thunder_ElectronicNoise_Play",
                            sound_noise_stop = "AKE_Ms12_UI_HUD_Thunder_ElectronicNoise_Stop",
                            sound_inside = "AKE_GEN_ENV_AMB_ThunderCloud_Inside_Ambience_Play",
                            sound_inside_stop = "AKE_GEN_ENV_AMB_ThunderCloud_Inside_Ambience_Stop" },
                 -- ((2026-11-08) `buildup`: the storm gathering over 3 rounds into the typhoon (sv_anomalies_dev.lua: Ctrl+],
                 -- Ctrl+'): each stage's share of Mission 12's storm sky (sky.fraction), its storm cells (cells: how many,
                 -- how big, how often each rolls, its chance x, flashes), the turbulence (scale a stage), the rain (from
                 -- rain.from_stage) and the callouts; stages 1-3 the rounds before Distant Thunder's, 4 its own)
                 buildup = { enabled = true,
                             sky = { asset = "/Game/Cloudly/CloudlySkyParams/Ingame/Mission012/CSP_ms12_260216.CSP_ms12_260216",
                                     -- ((2026-11-08) a change of the clouds' heights, rain clouds or rain pillar blacks the
                                     -- whole sky out for a moment (hard rule 61: the user's recordings of 0.74.36 and the sky
                                     -- probe's of 0.74.38); clouds "safe": every other cloud value ramped, never those in
                                     -- `unsafe`; the rain pillar off)
                                     fraction = { 0.3, 0.6, 0.85, 1.0 }, ramp_s = 300, clear_s = 90, clouds = "safe",
                                     unsafe = { "StartHeightInKm", "RainCloud", "RainPillar" }, rain_pillar = false, pillar_km = 6,
                                     -- ((2026-11-08) the user: "how about a cutscene transition?": the unsafe ones change only
                                     -- under a fade to black at each stage change and as it clears)
                                     transition = { enabled = true, out_s = 0.5, hold_s = 0.6, in_s = 0.7, sound = "AKE_Environment_Thunder_Play" },
                                     -- ((2026-11-08) the user: "we need to bring in the storm cloud layer from another map")
                                     -- Mission 12's cloud layout behind the fade from stage from_stage (Ctrl+; probes it)
                                     layout = { enabled = true, from_stage = 2, force = true, set_resources = false,
                                                asset = "/Game/Cloudly/CloudlySkyParams/Ingame/Mission012/CVC_ms12_250708.CVC_ms12_250708" },
                                     dark = { enabled = true, ev = -1.5, sun_x = 0.4, skylight_x = 0.5 } },
                             cells = { n = { 2, 4, 6, 6 }, radius_m = { 2000, 3000, 4000, 4500 }, top_m = 7000, from_km = { 6, 28 },
                                       roll_s = { { 6, 9 }, { 4, 6.5 }, { 2.5, 4.5 }, { 2, 3.5 } }, chance_x = { 0.6, 0.8, 1.0, 1.0 },
                                       drift_ms = 15, wrap_km = 35, flash_s = { { 6, 10 }, { 3, 6 }, { 2, 4 }, { 1.5, 3 } },
                                       flash_z_m = 2500, flash_scale = 8, thunder_km = 12 },
                             -- ((2026-11-08) "how can we get lightning to play inside the clouds?": a cloud light
                             -- (class: the game's, Cloudly's effect light on a timeline; method "effect": Survival's own)
                             -- with the bolt and its thunder after the sound's time; Ctrl+\ probes the ways)
                             lightning = { enabled = true, from_stage = 1, method = "bp",
                                           class = "/Game/Blueprints/Cloudly/CloudLight/BP_CloudLight_Ms009_FarExplosion.BP_CloudLight_Ms009_FarExplosion_C",
                                           every_s = { { 14, 24 }, { 7, 12 }, { 4, 7 }, { 2, 4 } },
                                           dist_km = { { 8, 16 }, { 6, 14 }, { 4, 12 }, { 3, 10 } }, alt_m = { 2500, 6000 },
                                           cell_share = 0.5, bolt = true, bolt_scale = 12, thunder = true, thunder_s_per_km = 2.9,
                                           thunder_max_s = 6, sound = "AKE_Environment_Thunder_Play", set_color = false,
                                           color = { 205, 215, 255 }, effect_intensity = 5.0e7 },
                             turbulence = { from_stage = 2, every_s = { 1.5, 3 }, scale = { 0, 0.5, 0.9, 1.4 },
                                            shake = "/Game/Blueprints/Vehicle/PLAYER/Camera/CameraShake/BP_CamShake_Turbulence" },
                             rain = { enabled = true, from_stage = 3, brightness = 10 },
                             sound = { distant = "AKE_Ms12_ENV_AMB_DistantThunder_Play", distant_stop = "AKE_Ms12_ENV_AMB_DistantThunder_Stop",
                                       clap = "AKE_Environment_Thunder_Play" },
                             text = { start = "WEATHER WARNING", start_sub = "DISTANT THUNDER IN ROUND %d",
                                      stage = { "WEATHER WARNING", "SEVERE STORM WARNING", "TYPHOON WARNING", "TYPHOON" },
                                      stage_sub = { "A STORM IS GATHERING", "STORM CELLS: STAY CLEAR OF THE LIGHTNING",
                                                    "IT ARRIVES NEXT ROUND", "DI..ANT TH..D..R" },
                                      clear = "THE STORM CLEARS", clear_sub = "SKIES CLEARING" } },
                 probe = { writes = 3, gap_s = 1.0 },
                 storm = { radius_m = 7000, min_interval_s = 0, max_interval_s = 0, curve = "MS_12", log_strikes = true,
                           class = "/Game/Blueprints/System/Lightning/BP_LightninigVolume_MS12.BP_LightninigVolume_MS12_C",
                           curve_table = "/Game/Blueprints/System/Lightning/CUR_LightningWeight.CUR_LightningWeight" },
                 fx = { enabled = true, every_s = 2.5, scale = 4.0, life_s = 3.0,
                        system = "/Game/VFX/Environment/Common/Lightning/CloudLightning/NS_CloudLightning" },
                 test = { radius_m = 7000, seconds = 60, stall_s = 3.0 },
                 text = { warn = "WARNING: %s", warn_sub = "%s: ITS STORM BLINDS YOU", down = "%s DOWN",
                          down_sub = "+%d ZOLLARS", row = "%s: %.1f KM", row_storm = "%s: IN ITS STORM",
                          key = "TEST: %s", key_now = "STARTING NOW", key_next = "NEXT ROUND",
                          storm_on = "TEST: STORM ON YOU", storm_on_sub = "%d S, %.1f KM", storm_stall = "TEST: STALL %.1f S",
                          storm_stall_sub = "LS_STALLTIME ON YOUR PLANE", storm_off = "TEST: STORM OFF" } }
-- TEST ONLY END
-- The sky (Scripts/sv_sky.lua; docs/re/FISHING.md 5): the day-night arc's owner. It never writes the stock sky asset
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
-- ((2026-11-08) the user, at round F+9: "this night is waaay to dark, but we need a way to make is so the sea doesn't
-- glow so badly, also theres no visible stars"; "research how the night map at Retaking of Theve II works": Mission 9,
-- docs/re/NIGHT_SKY.md) The night is Mission 9's whole night, not part of it: its exposure (0.5 / 9, one stop brighter
-- than its +0.5: Comona has no night city) together with its night ambient (the sky light at Mission 9's night cubemaps'
-- level: x skylight_x of Mission 4's day ones, 0.1 was 20,000-45,000 times too bright: the sea mirrored it), the
-- light's specular spec (0.01: no moon glint on the sea), its stars (Mission 9's, for its exposure; the catalog and the
-- moon's texture put on the sky actor, which Mission 4's lacked: stars.catalog, night.moon_texture), its moon (phase,
-- phase angle, brightness moon_frac), its night sky's multiple scattering (ms, ms_ap: navy, not black), the cockpit's
-- screens and gauges dimmed (mfd, meter, ice: MPC_MEC_EmissiveControl, mpc_mec), the city's and the airfield's glow up
-- (emissive 10000), the effects' EV down (vfx_ev -2), far small lights drawn (light_radius: r.MinScreenRadiusForLights),
-- and the planes' own lights on (nav_lights: their navigation, anti-collision and formation lights; 0 in every stock
-- mission). The cockpit view's own exposure (min 11) comes down with it.
-- ((2026-11-08, 0.74.25) the user's screenshots of rounds 15 and 16: "it transitions to night well but on the final tick,
-- the sea becomes green"; a joiner's log (0.74.23): the round-15 break blended into the night by round 16's start, so the
-- full night itself is what turns the sea a bright teal. The night is now the look of the break's last seconds, the frame
-- the user's first screenshot shows (about 80% of the way from the sunset to Mission 9's night): exposure 2.3 / 10 / +0.6
-- (Mission 9's 0.5 / 9 / +1 let the camera open ~5 times more, and the sea mirrors the drawn night sky), sky light x4e-5,
-- glow 4000, the effects' EV 0, the night sky's glow 2.7 / 2.6, the cockpit 6e-4 / 0.007 / 6e-4, light_radius 0.01)
CFG.sky = { enabled = true, readback_s = 5,
            mpc_env = "/Game/Base/Material/MPC/MPC_Env_Control.MPC_Env_Control",
            mpc_vfx = "/Game/Base/Material/MPC/MPC_VFX_Control.MPC_VFX_Control",
            mpc_mec = "/Game/Base/Material/MPC/MPC_MEC_EmissiveControl.MPC_MEC_EmissiveControl",
            test_sun = { -2.0, -105.0 }, test_copies = { 4.0, -120.0 },
            night = { sun_el = 35.0, sun_az = -130.0, factor = 0.5, rgb = { 0.888, 0.965, 1.0 }, sun_disc = 0.5683,
                      moon_el = 35.08, moon_az = -130.03, moon_phase = 0.143, moon_phase_angle = 3.415, moon_frac = 1.0e-5,
                      moon_texture = "/Cloudly/Textures/StarsBackground/NasaCGIMoonKitLow.NasaCGIMoonKitLow",
                      exposure = { 2.3, 10.0, 0.6 }, skylight_x = 4.0e-5, skylight_rgb = { 0.88, 1.0, 1.0 }, spec = 0.01,
                      emissive = 4000.0, vfx_ev = 0.0, ms = 2.7, ms_ap = 2.6, mfd = 6.0e-4, meter = 0.007, ice = 6.0e-4,
                      nav_lights = 1.0, light_radius = 0.01 },
            stars = { catalog = "/Cloudly/StarCalalogs/ASCIIYaleBrightStarCatalog5.ASCIIYaleBrightStarCatalog5",
                      intensity = 2.26, background = 0.55, radius = 4.45, fraction = 0.5, rotation = { 0.0, 0.0, 0.0 },
                      mask_on = true, mask_start = 0.110, mask_len = 0.716, fade = 14.77, scint = 0.85,
                      moon_on = true, moon_angle = 0.0, moon_len = 0.235 },
            arc = { enabled = true, path = "asset", apply_s = 2.0, apply_break_s = 1.0, blend_s = 5.0, round_s = 240, within_x = 0.75,
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
-- bank Survival's level loads (docs/re/MUSIC_RADIO_CAMERA.md); a name the game doesn't have is dropped.
-- pause_player: free flight's Music Player row in Survival's pause menu; once the player opens it, Survival stops
-- changing the music for the rest of the run.
-- enabled = false (user, 2026-10-22): no round music at all, the Music Player is the only music (the mission-start
-- track played over it; tools/survival_events.py MUSIC is None too). true brings the round rotation back.
-- hold_clock: the Music Player ends each track by its own clock, which ran on through pauses, so every pause cut the
-- track short (user, 2026-10-22: "music skipped on round change"); dlls/main.dll 0.12.0 holds it while the BGM is
-- paused (SV_MusicClock, docs/re/MUSIC_RADIO_CAMERA.md "Track skips in Survival").
CFG.music = {
    enabled      = false,
    pause_player = true,
    hold_clock   = true,
    -- ((2026-11-08) the user: "add all the named music into the music player") Survival's music player (sv_music.lua; never
    -- written to the save): the menu tracks hidden, every other stock track unlocked, the room left to player_max filled
    -- with a random draw from player_from's groups (jukebox, online, battle, endings), new each time a run starts
    player_all    = true,
    player_max    = 120,      -- the music player's limit (its list shows 120; more crashed the game)
    player_from   = "jukebox",
    player_loop_s = 240,      -- a track that loops for ever (the online match tracks) moves on after this; 0 = never
    -- the stock tracks hidden in Survival (the user: "Delete the briefing debriefing cutscene tracks", "hangars too")
    player_hide   = { "AKE_Bgm_MUSICPLAYER_BGM_TITLE_Play", "AKE_Bgm_MUSICPLAYER_BGM_MAINMENU_Play",
                      "AKE_Bgm_MUSICPLAYER_BGM_BRIEFING01_Play", "AKE_Bgm_MUSICPLAYER_BGM_BRIEFING02_Play",
                      "AKE_Bgm_MUSICPLAYER_BGM_BRIEFING03_Play", "AKE_Bgm_MUSICPLAYER_BGM_BRIEFING04_Play",
                      "AKE_Bgm_MUSICPLAYER_BGM_HANGAR01_Play", "AKE_Bgm_MUSICPLAYER_BGM_HANGAR02_Play",
                      "AKE_Bgm_MUSICPLAYER_BGM_HANGAR03_Play", "AKE_Bgm_MUSICPLAYER_BGM_DEBRIEFING01_Play",
                      "AKE_Bgm_MUSICPLAYER_BGM_DEBRIEFING02_Play", "AKE_Bgm_MUSICPLAYER_BGM_DEBRIEFING03_Play",
                      "AKE_Bgm_MUSICPLAYER_BGM_MISSIONFAILED_Play" },
    start_track  = "AKE_Bgm_Ms08A_Play",
    restart_s    = 15,
    tracks  = { "AKE_Bgm_Ms02A_Play", "AKE_Bgm_Ms04A_Play", "AKE_Bgm_Ms05a_Play", "AKE_Bgm_Ms07A_Play",
                "AKE_Bgm_Ms11A_Play", "AKE_Bgm_Ms12a_Play", "AKE_Bgm_Ms14A_Play", "AKE_Bgm_Ms17A_Play",
                "AKE_Bgm_Ms18A_Play", "AKE_Bgm_Ms20A_Play", "AKE_Bgm_Ms21A_Play", "AKE_Bgm_Ms22A_Play",
                "AKE_Bgm_Ms24A_Play" },
    special = { "AKE_Bgm_Ms09B_Play", "AKE_Bgm_Ms20D_Play", "AKE_Bgm_Ms23B_Play", "AKE_Bgm_Ms27A_Play",
                "AKE_Bgm_Ms28C_Play", "AKE_Bgm_Ms30A_Play" },
}
-- Round HUD. Positions are on the game's HUD design canvas (3840x2160, scaled to the screen; docs/re/HUD_LAYOUT.md).
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
                                    ["MARKET STALL"] = { 0.90, 0.80, 0.60 },
                                    -- (2026-11-08: Kaska's channel, steel grey)
                                    ["INTERCEPT: KASKA"] = { 0.70, 0.76, 0.84 }, ["INTERCEPT: EMBDIR LAUNCH"] = { 0.52, 0.60, 0.68 } },
                         -- a line's speaker code ("MC|...") to the name on the strip; a code not here is the name
                         speakers = { MC = "CONCERT MC", FOOD = "FOOD TRUCK", MARKET = "MARKET STALL",
                                      -- ((2026-11-08) the shuttle round's intercepted channel: Scripts/sv_kaska.lua)
                                      KASKA = "INTERCEPT: KASKA", EMBDIR = "INTERCEPT: EMBDIR LAUNCH",
                                      CTRL = "COMONA CONTROL" },                -- ((2026-11-11) the retake's rockets)
                         -- ((2026-11-08) the user: "all of the Audrey and Valka subtitles must play One After Other, and
                         -- they can't be reused, and they take priority over everyone elses subtitles") priority: their
                         -- lines go before every other speaker's waiting line (after theirs already waiting: in the order
                         -- said, an exchange whole), a full queue drops another's line for them, never theirs, and
                         -- another's line on the strip gives way to them once it's been up prio_min_s (an exchange with
                         -- one of theirs goes ahead whole, in its order). Then: "do this for all characters actually have
                         -- it so none of the characters repeat lines": once_a_run, every speaker's line said at most once a
                         -- run (one said already is refused; the pickers choose among the ones not said yet, and say
                         -- nothing once all are; a line with values in it is a repeat only word for word); repeat_ok:
                         -- speakers allowed to repeat (none)
                         priority = { "AUDREY", "VALKA" }, prio_min_s = 1.0, once_a_run = true, repeat_ok = {} },
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
        -- ((2026-11-11) its core's health once it's open: the row's CORE, and the callout as it drops past 75 / 50 / 25 %)
        alicorn_core_pct = "%d%%", alicorn_core_left = "ALICORN CORE: %d%%", alicorn_core_left_sub = "KEEP HITTING IT",
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
        sp_captured_sub = "RETAKE IT NEXT ROUND: STOP THEIR ROCKETS",
        sp_lost      = "SPACEPORT LOST",
        sp_lost_sub  = "%d SHIPS STAY OFFSHORE FOR THE RETAKE",
        sp_held      = "SPACEPORT HELD",
        sp_held_sub  = "+%d ZOLLARS",
        sp_retake_go = "SPACEPORT RETAKE",
        sp_retake_go_sub = "DESTROY THE GARRISON, THE ISLAND'S DEFENCES AND THE ROCKETS",
        sp_retake_row = "GARRISON: %d  FLEET: %d SHIPS",
        sp_rocket_launch = "ROCKET %s LAUNCHED",
        sp_rocket_launch_sub = "SHOOT IT DOWN BEFORE IT REACHES ORBIT",
        -- ((2026-11-11) the rockets' warning, halfway, the NEXT row's rockets and the reward withheld: sv_spaceport.lua)
        sp_rocket_warn = "ROCKET %s: LIFTOFF IN %d S", sp_rocket_warn_sub = "GET TO THE SPACEPORT'S PADS AND STOP IT",
        sp_rocket_half = "ROCKET %s HALFWAY TO ORBIT", sp_rocket_half_sub = "%.0f KM UP: SHOOT IT DOWN NOW",
        sp_rk_row = "  ROCKETS: %s", sp_rk_pad = "%s IN %s", sp_rk_up = "%s %.1f KM", sp_rk_climb = "%s CLIMBING",
        sp_rk_down = "%s DOWN", sp_rk_esc = "%s IN ORBIT", sp_rk_gone = "%s GONE",
        sp_retaken_esc_sub = "NO REWARD: %d ROCKET(S) REACHED ORBIT",
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
