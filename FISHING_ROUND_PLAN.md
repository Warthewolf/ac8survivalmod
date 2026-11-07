# GONE FISHIN' special round: plan (draft, 2026-11-05)

A comedy special. A Comona fisherman has heard the air force is "in the area" and calls in an airstrike on his
fishing grounds. The player gets about 3 minutes to blow up hidden shoals in the sea off Comona. Some shoals are
full of fish and some are empty. When the round ends the fisherman weighs the catch and the player gets graded
and paid on it. It's dynamite fishing, done with a multirole fighter.

Status: plan only. Nothing is built and nothing is tested in game. Mark each mechanism [T] until a test confirms it,
as AGENTS.md says.

## 0. Decisions of 2026-11-06 (user) and what the code has gained since this draft
Work branch: `feature/fishing` from COOP2MP 0.73.84 (c8410b4), worktree `E:\ACE8 SM fishing`. This draft was written
on a branch cut from 0.70.6 (`plan/fishing-round`); build nothing on that branch.

The user's answers to section 5:
- Q1: the fisherman stays **SAL**.
- Q2: **SAL's boat is in from the first build**: an allied boat near the grounds; a hit on it costs the player who hit it
  kg ("THAT IS MY BOAT"). Research: which stock vessel, held at a health floor, unarmed, hits attributed.
  Then (user, 2026-11-06): "SAL boat can just be an ally, dont worry about it too much." So: an ordinary allied boat
  (VE027_boat2, blue box, held at a health floor). The kg penalty only where a hit shows on this game's own copy; no
  red-box fallback, no new co-op message for it, no extra work if the test shows allies can't be damaged.
- Q3: catches **fully random**: one shuffled deck for the round (section 3.2's recommended deck), no per-ground odds.
- Co-op (not in the draft): **each player's own haul**. The host draws a catch from the deck for each shoal destroyed
  and credits it to the player who destroyed it (the host's kill attribution, as "dn" names a killer); each player
  gets their own weigh-in, grade and pay; the end card also shows the team total. A boat hit costs its shooter.
- Q4 (pay) and Q5 (earliest round): open. Proposed: an A pays about what the no-risk specials pay. The other
  specials pay 4,000-12,000 Z + 160-400 Z a round, all with enemies, so an A of ~6,000 Z and an S of ~9,000 Z.
  Earliest round 7: `specials.early` gives rounds 2-6 to the Shuttle alone.

The story (user, 2026-11-06): Comona Island is holding a festival and needs as much fish as possible for it, so SAL
enlists the local air force (the players) to catch it. The draft's lines (an angler whose fish are hiding) get
rewritten around the festival: SAL is catching for the whole island, and the weigh-in is what the festival gets.

The day-night arc (user, 2026-11-06): the fishing round starts the run's sunset. With F = the fishing round:
| Round | Sky |
|---|---|
| F+1 .. F+5 | the sun sinks a step each round |
| F+6 | sunset: THE FESTIVAL (below) |
| F+7 | night |
| F+8 .. F+11 | the sun rises on the map's real sunrise side (east) and climbs slowly, a step each round, to midday |
| after | midday, held for the rest of the run |
Star brightness at the maximum (from when the stars show through the night). Changes blend gradually, never a jump in
a fight. Research under way: AC8's sky clock (Survival's level runs Mission 4's lighting at 10:10), the stars' and
moon's parameters, east on Comona, co-op sync, VALKA's red sky on top of the arc, restore on quit / restart / new run.
The sunrise takes "the next few rounds" (user): 4 rounds by default (a setting). Stars at maximum from when they show
at sunset through the night (default until the user says otherwise).

GONE FISHIN' comes at most ONCE PER RUN (user, 2026-11-06), so the arc and the festival play once.

VALKA waits for the arc (user, 2026-11-06): "if a Fishing Round is triggered, VALKA rounds dont start until the festival
is completed and the sun has risen to midday again". From GONE FISHIN' until the festival is over AND the sky is back
at midday (the end of the sunrise, F+11 by default), VALKA's kind is not ready (SPC.kinds.valka.ready / the pacing bag
never draws her; the host decides, so co-op follows). Her red sky then never has to sit on the sunset or the night.

THE FESTIVAL (round F+6, at sunset; user, 2026-11-06): it happens at the airfield. About 30 s of dialogue thanking the
pilots, then an air raid siren plays at the airfield, searchlights spawn round it, and a large enemy bomber formation
is spotted coming in from the NORTH, WEST and SOUTH: all Tu-160s. They launch cruise missiles from a distance, and the
players can shoot the missiles down (copy Mission 30's targetable cruise missiles). Research under way: Mission 30's
launch records and missile rows, a stock air raid siren, stock searchlights, three Tu-160 formations at once (the world
data has one 4-ship heavy unit today: more needed, a full build), standing off rather than flying over the runway.

What the draft predates (0.70.6 -> 0.73.84), to build against:
- Co-op is host-authoritative: the shoals and the boat are spawned through the SV_Spawn wrapper (co-op ids on every
  game, 0.73.80), the deck and catches live on the host, catch lines, subtitles and the weigh-in go to the joiners.
- Money is zollars (Z), not credits; specials' pay goes through the special split in co-op (`special_split`).
- Units come off the spawner's list with SV_Recycle (SPC.recycleLater, 0.73.83), not UnregisterUnit + Destroy.
- Specials plug in through SPC.kinds (ready / busy / over / row) and the 0.73.80 pacing bag (chance_step, max_gap).
- Ctrl+F10's shore marker is no longer in the code: the grounds come from data the repo already has (coast marks,
  the amphibious lanes, the Spaceport fleet's positions).
- Radio test T1 (RADIO_LOCALISATION.md, text-only SV_ lines) was never run: subtitles start on route 1 (Survival's
  HUD). The user asked for fewer HUD callouts in 0.72.1; this strip shows only during this round.
- The leaderboard Worker's SPECIALS list needs `fishing` (a redeploy) if a fishing round should count.
- Test keys are TEST ONLY (stripped from every release zip).

---------------------------------------------------------------------------------------------------------------------
## 1. The round in one paragraph
The round is picked like any other special (kind `fishing`, in `CFG.specials.rotation`). No enemy aircraft spawn and
nothing attacks the airfield. When the round starts, 24 invisible targets ("shoals") are placed on the water in
three fishing grounds off Comona. Each one has a TGT box so the player can find it. Each shoal is secretly given a
catch when the round starts: nothing, junk, or one of five fish with a weight. Destroying a shoal shows its catch
straight away (HUD callout, e.g. `+38 kg  YELLOWFIN TUNA`, or `NOTHING`) and the fisherman reacts on the subtitle
line. When the 3:00 timer runs out, or every shoal is gone, the fisherman weighs the haul, a results card shows
kg, grade and pay, and the normal intermission starts.

## 2. Player-facing rules
| Thing | Value (CFG default) | Note |
|---|---|---|
| Time limit | 180 s | HUD countdown, shown only during this round (the normal round timer counts only intermissions, SURVIVAL_SPEC 6) |
| Shoals | 24 (8 per ground, 3 grounds) | `count_by_preset`: casual 20, standard 24, ace 28 |
| Empty shoals | about 30 % | they give nothing, and the fisherman complains |
| Weapons | anything | missiles, gun and bombs all count. Special weapons are fine ("that's the spirit") |
| Enemies | none | `escort_kinds` doesn't list it: no escorts, even late in a run |
| Failure | none | a bad haul just pays little. The run never ends here |
| Airfield | open | landing works as normal. Time spent landed still counts down |

### Catch table (rolled per shoal at round start, weights add up to 100)
| Catch | Chance | kg per shoal | Callout |
|---|---|---|---|
| Nothing | 30 | 0 | `NOTHING` |
| Old boot / junk | 8 | 0 | `JUNK` (gets its own lines) |
| Sardines | 22 | 15-30 | `SARDINES` |
| Mackerel | 18 | 25-45 | `MACKEREL` |
| Yellowfin tuna | 13 | 40-90 | `YELLOWFIN TUNA` |
| Swordfish | 7 | 80-140 | `SWORDFISH` |
| "The Big One" (giant grouper) | 2 | 250-400 | `THE BIG ONE` (only one per round at most) |

Average about 33 kg per shoal, so a clean 24-shoal sweep comes to roughly 800 kg.

### Grading and pay (end card)
| Grade | Haul | Fisherman's verdict |
|---|---|---|
| S | ≥ 900 kg | "LEGEND OF THE SEA" |
| A | 650-899 kg | "A FINE CATCH" |
| B | 400-649 kg | "HONEST WORK" |
| C | 150-399 kg | "SOUP FOR A WEEK" |
| D | < 150 kg | "THE GULLS EAT BETTER" |

Pay: `credits_per_kg` (default 12) × kg, plus a grade bonus (S 3000 / A 1500 / B 500 / C 0 / D 0). It grows with
`pay_per_round` the way the other specials' rewards do, so a late fishing round isn't a wasted round economically.
Big One bonus: +1000. The end card shows: shoals hit / 24, empty shoals, best fish, total kg, grade, credits.
Also optional: record the kg to the leaderboard (`sv_leaderboard.lua`) as a separate "best haul" stat.

---------------------------------------------------------------------------------------------------------------------
## 3. How it gets built (copy stock or existing Survival patterns first, as MISSION_REFERENCE.md says)

### 3.1 The targets: invisible, killable, boxed
Static targets don't need paths, which avoids most of the hard rules around paths (1, 2, 35). Pick one of the
following options in a research step before building anything:

- **A (preferred): `dummy_common` objects.** Mission 22's shuttle near-miss points (`AA_Obj_01_Ground0_Shuttle_Dummy_*`,
  already in Survival's WD, SPECIAL_ROUNDS 12a) have no mesh, so they're already invisible. They're invincible, so the
  round gives them health with `LiveSetMaxHealthExecution` (the shuttle's MissionStart record, copied the same way) and
  `bShowHUDBox` + `TargetMarkType 1` (hard rule 32, `port_unit tgt=True`). One build-time desc per fishing ground
  (`SV_Unit_Fish1..3`), 8 or more AI objects each, placed on the water at z ≈ sea level + 2 m. Research: confirm a
  dummy can be locked on, takes damage and gets destroyed, and that the missile's proximity fuse actually detonates
  next to it.
- **B (fallback): a ported sea craft with its mesh hidden.** Mission 13's LCAC (`lcac_common`, already ported by
  `port_unit`, hard rule 31), spawned in place with no path. At spawn, Lua calls `SetActorHiddenInGame(true)` on it
  (or hides its body StaticMeshComponent). Its collision stays, so hits still register. Watch out: the wake or other
  VFX may still draw. If they do, that's acceptable ("something's stirring down there").
- Either way, add a splash when a shoal dies: `LiveSetActiveVFXExecution` on a placed VFX desc, or
  `BP_MO103_GroundSmokeM` as for the shuttle's near misses. A water-column explosion would look best. Find a stock
  one: Mission 13 / Mission 9 shore and naval hits are the likely places.

The three grounds are in the sea next to Comona Airport, within 6-12 km so the round fits in 3 minutes:
**North Shoal**, **Lighthouse Bank**, **The Deep Hole**. The user marks them with Ctrl+F10, exactly as the
amphibious round's water points were marked (`config/coast_marks.txt`; hard rule 27: traces only work near the
player, so the marks have to come from flying there). Inside a ground, the shoals are scattered randomly at build
time or (better) at spawn, within 800 m of the mark.

### 3.2 Counting kills and catches (Lua, new part `Scripts/sv_fishing.lua`)
Copy the pattern from `sv_amphib.lua`: at a 250 ms tick, `SV_UnitAlive("SV_Unit_Fish<g>")` per ground. A drop in the
count means shoals died. To know which shoal died (and so which catch it held), either:
- check each AI object (actor validity / health read, as the Alicorn's parts do in `sv_alicorn.lua`), or
- don't tie the catch to a specific shoal at all: keep a shuffled deck of 24 catches and draw from it each time a
  shoal dies. The player can't tell the difference and it needs no per-object tracking. **Recommended.** It also
  makes "The Big One" easy to cap at one.

Wingmen bought in the STORE: kills by allies still count (SURVIVAL_SPEC 8, "allied kills should still pay me").
The fisherman gets a line for it ("your friend is good too!").

State: `D.special = { kind = "fishing", state = "intro" | "fishing" | "weigh" | "done", t0, deck, kg, hits, empty,
best }`. Plug into `sv_rounds.lua` as the other specials do (around line 589): the round isn't over while `state` is
`fishing`. When the timer runs out, the remaining shoals are removed (UnregisterUnit + Destroy, hard rule 16, as
SV_Spawn does), `state = "weigh"`, the end card shows, pay goes in, and then the intermission starts.

### 3.3 Subtitles: two routes
- **Route 1 (works today): Survival's own HUD.** Add a subtitle strip to `sv_hud.lua` below the callout area
  (speaker name in a colour, line in white, ~4 s each, queued, as `hudCallout` already queues). Built from TextBlocks
  like the rest of the HUD (hard rule 18, confirmed). This is the default.
- **Route 2 (nicer, needs test T1 of RADIO_LOCALISATION.md first): real radio subtitles.** DT_SV_Radio rows with
  `TextID = SV_Radio_Fish_<n>` (text only, no voice), `SV_SetText` sets the English line, and `RE_SV_Radio_Fish_*` is
  played with `SV_Event`. That gives the game's own subtitle box and a portrait (pick a stock civilian one from
  `T_HUD_SubtitleSpeakerPortrait_*`). Switch to this route once T1 shows that text-only SV_ lines are displayed.
- No voice in either route. Stock voice clips can't say these words, and AC7 voice lines are never used (AGENTS.md).
  A small radio-static blip from `sv_sound.lua` on each line would help sell it.

All lines live in `CFG.specials.fishing.lines` (lists by event, one picked at random, never the same line twice
running), so players can edit them and translations can override them.

### 3.4 Config (`sv_config.lua`, plus a `[fishing]` section in `survival.default.ini`: Codex's area, coordinate)
```lua
fishing = { name = "GONE FISHIN'", time_s = 180, count = 24, count_by_preset = { casual = 20, standard = 24, ace = 28 },
            grounds = { "North Shoal", "Lighthouse Bank", "The Deep Hole" }, spread_m = 800,
            catch = { none = 30, junk = 8, sardine = 22, mackerel = 18, tuna = 13, swordfish = 7, bigone = 2 },
            credits_per_kg = 12, pay_per_round = 0.04, bigone_bonus = 1000,
            grades = { { "S", 900, 3000 }, { "A", 650, 1500 }, { "B", 400, 500 }, { "C", 150, 0 }, { "D", 0, 0 } },
            speaker = "SAL", command = "COMONA CONTROL", line_s = 4.0, lines = { ... section 4 ... } },
```
Rotation: add `"fishing"` to `specials.rotation`. It's a breather, so it should be allowed from round 4 (after
`early`), keep the 10-round cooldown, and not be allowed twice running. Proposed: it may come straight after a hard
special (Ladon / Alicorn / VALKA) as a palate cleanser.
Test key: add one next to the other specials' test keys (SURVIVAL_SPEC 10).

### 3.5 Files touched
| File | Change | Owner |
|---|---|---|
| `mod/UE4SS/AC8SurvivalMode/Scripts/sv_fishing.lua` (new) | round state, deck, catches, timer, grading, lines | Claude |
| `Scripts/main.lua` | add `sv_fishing` to MODULES (after `sv_amphib`), bump VERSION | Claude |
| `Scripts/sv_rounds.lua` | pick / start / busy / over hooks for `fishing` | Claude |
| `Scripts/sv_hud.lua` | subtitle strip, round timer, end card | Claude |
| `Scripts/sv_config.lua` | `specials.fishing`, rotation | Claude |
| `config/survival.default.ini` + INI_ALIAS | `[fishing]` | Codex |
| `tools/build_survival.py` | `SV_Unit_Fish1..3` descs (dummy or ported LCAC), boxes, health | Claude |
| `tools/survival_events.py` | max-health / splash VFX records, `RE_SV_Fish_*` | Claude |
| `tools/re/FISHING.md` (new) | what was found and confirmed | Claude |
| `SURVIVAL_SPEC.md` | section 11 once the user confirms the design | — |

Checks after each edit: `python -X utf8 tools/checks/lua_check.py mod/UE4SS/AC8SurvivalMode/Scripts/*.lua`
(200 locals per part, 15-char native names, the `a and pcall()` pattern) and `tools/checks/ini_check.py`.

### 3.6 Milestones
1. **Research (no build):** pick target option A or B and the splash VFX. The user marks the three grounds in game.
2. **Targets in:** one ground, 8 boxed invisible shoals, a test key spawns them, and the log shows kills.
   [T]: lock-on, missile fusing, gun hits.
3. **Round loop:** timer, deck, catch callouts, end card, pay, and back to intermission. [T]
4. **Subtitles:** Route 1 lines. Then T1, then Route 2 if it passes. [T]
5. **Polish:** splash VFX, radio blip, leaderboard best haul, ini section, release notes.

### 3.7 Risks
- `dummy_common` may not be lockable or damageable even with health set. Fallback B.
- Missiles may not fuse on a meshless target at sea level and fly into the water instead. In that case use a hidden
  mesh (B), or let hitting the water within N m of the shoal count, using Lua distance from impact (the near-miss
  trigger type 10 that M22 uses, `MissedWeapon_*`).
- Terrain traces don't work far from the player (rule 27). Use fixed marks, not run-time sea checks.
- Wingmen may chase empty water forever. Order them to hold or follow (ally orders from the economy build).

---------------------------------------------------------------------------------------------------------------------
## 4. Subtitles
Speakers: **SAL** (an old Comona fisherman on an open channel, delighted and opinionated) and **COMONA CONTROL**
(the usual dry controller, slowly giving up). `{kg}`, `{fish}`, `{grade}`, `{credits}` and `{left}` are filled in by Lua.
Keep each line under ~70 characters so it fits the strip on one line.

### 4.1 Round start (in order, ~4 s apart, before the timer starts)
1. CONTROL: All aircraft, we have an... unusual request on an open channel.
2. SAL: Hello? Is this the air force? My nephew says you have bombs.
3. CONTROL: Sir, this is a military frequency.
4. SAL: The fish are hiding from me. Forty years, they never hid like this.
5. SAL: I marked where they are. You go boom, I collect. Very simple.
6. CONTROL: ...Command has approved it. Don't ask me why. You have three minutes.
7. SAL: Three minutes! Go, go! The tide waits for no one!

### 4.2 Timer starts
- CONTROL: Targets are on your HUD. Fishing grounds are hot.
- SAL: Remember, I am paying in fish. Maybe also money.

### 4.3 Catch reactions (one picked at random each time)
**Nothing**
- SAL: Nothing! You blew up water. Very expensive water.
- SAL: Empty. The fish laugh at us now.
- SAL: That was a rock. I think. A dead rock now.
- SAL: My cousin promised fish were there. My cousin lies.
- CONTROL: Confirmed kill on... the ocean.

**Junk**
- SAL: A boot! Only one. Who loses one boot?
- SAL: A shopping cart? How did a shopping cart get out here?
- SAL: That's my old net! I've been looking for that for six years.
- SAL: A tire. I will make a swing for the grandchildren.

**Sardines**
- SAL: Sardines! Small, but many. Like my family.
- SAL: Little ones! Good for the cats. Very good for the cats.
- SAL: {kg} kilos of sardines. Already in a tin, almost.

**Mackerel**
- SAL: Mackerel! Now we are fishing!
- SAL: Beautiful mackerel. Pre-cooked, even. Thank you.
- SAL: {kg} kilos! My wife will stop asking where I was.

**Yellowfin tuna**
- SAL: TUNA! Oh, you are good. You are very good.
- SAL: Yellowfin! I am crying a little. It's the salt.
- SAL: {kg} kilos of tuna! I will name my boat after you.
- CONTROL: Sir, please stop cheering on this frequency.

**Swordfish**
- SAL: A swordfish! He wanted to fight. You won.
- SAL: Look at the size of him! My nephew will never believe me.
- SAL: Swordfish! Even the air force cannot dodge that nose. Except you.

**The Big One (once per round)**
- SAL: ...
- SAL: THE BIG ONE. Forty years I chase him. FORTY YEARS.
- SAL: {kg} kilos! I need a bigger boat. I need two boats!
- CONTROL: ...Okay, that was impressive.

### 4.4 Situational
**First hit of the round**
- SAL: BOOM! Yes! That is how my grandfather did it, but smaller.

**Three empties in a row**
- SAL: Maybe aim where the fish are? Just a suggestion.
- CONTROL: He has a point, and I hate that he has a point.

**Gun kill**
- SAL: With the little gun! Like a spear fisherman. Respect.

**Kill by a wingman**
- SAL: Your friend is good too! Tell him the fish are over there.

**Nothing hit for 30 s**
- SAL: Hello? Are you fishing or sightseeing?
- SAL: The fish are not going to explode themselves, my friend.

**Player lands at the airfield mid-round**
- SAL: You stop for coffee? The fish don't stop for coffee!

**Every shoal cleared early**
- SAL: You took all of them? There are no more fish in the sea!
- CONTROL: Great. Now there's an environmental report to file.

### 4.5 Timer warnings
- 2:00 — CONTROL: Two minutes left on the... fishing operation.
- 1:00 — SAL: One minute! Hurry, the gulls are coming!
- 0:30 — SAL: Thirty seconds! Anything that swims!
- 0:10 — CONTROL: Ten seconds. Wrap it up.
- 0:00 — SAL: Stop, stop! My boat is full! Let me weigh!

### 4.6 Weigh-in (after the timer, then the end card)
- SAL: Okay, okay. Let me see what we have here...
- SAL: {kg} kilos total. Hm. Hmm.

Then by grade:
- **S:** SAL: Legend of the sea! I will tell this story until I die. And after.
- **S:** SAL: The whole harbor will eat tonight. Free fish for the pilots!
- **A:** SAL: A fine catch! You can come fishing with me any time.
- **A:** SAL: Good work. Not my grandfather's work, but good.
- **B:** SAL: Honest work. Honest fish. I pay you honest money.
- **B:** SAL: Not bad. Not good. A Tuesday kind of catch.
- **C:** SAL: Soup for a week. Small soup.
- **C:** SAL: Well... the cats are happy.
- **D:** SAL: The gulls eat better than this. Next time I call the navy.
- **D:** SAL: You blew up more water than fish. I am disappointed.

Sign-off (any grade):
- SAL: {credits} credits, as promised. Most of it.
- CONTROL: Fishing operation complete. Resume normal hostilities.
- SAL: Same time next week? ...Hello? Hello?

### 4.7 End card text (HUD)
```
GONE FISHIN'  —  WEIGH-IN
SHOALS HIT  18 / 24      EMPTY  6
BEST FISH   SWORDFISH 122 kg
TOTAL HAUL  712 kg       GRADE  A
PAYMENT     +10,044 CR
```

---------------------------------------------------------------------------------------------------------------------
## 5. Open questions for the user (1-3 answered 2026-11-06: section 0)
1. ~~Fisherman's name~~: SAL.
2. ~~His boat~~: in from the first build.
3. ~~Random or hinted shoals~~: fully random.
4. Pay scale: is roughly 10k Z for an A grade about right next to the other specials' rewards? (Proposed in section 0:
   ~6,000 Z for an A, ~9,000 Z for an S.)
5. Should it be possible to get it as early as round 4, or only from round 7 like the other specials? (Proposed: 7.)
