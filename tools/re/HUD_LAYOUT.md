# The game's HUD layout (reverse-engineered 2026-10-22, for Survival's own run-time HUD)

Tool: `python tools/re/hud_layout.py <zen widget pkg>...` prints a widget blueprint's tree with every slot's anchors,
offsets, alignment and the resulting rectangle on the design canvas, plus texts (default string, font, colour),
images (brush, size) and embedded widget blueprints. Pull packages first with `tools/get_stock.sh`
(the 110 HUD widgets: `build/scan/hud_wbp.txt`; full dump of all of them: `build/scan/hud_layout_all.txt`).
Run-time check: Ctrl+F7 in game (Ctrl+F9 before Lua 0.38.3) writes the live HUD tree with on-screen geometry to
`Mods/AC8SurvivalMode/hud_dump.txt` (also written automatically 15 s into Survival).

## Design canvas
- Everything is laid out on a fixed **3840x2160** canvas (`HUD4K`). The flight HUD's root
  `WBP_HUD_Chronicle_MainFlight_000` is `BaseCanvas`, 3840x2160, centred; layers in draw order:
  LowestPriorityCanvasWorldToScreenDraw, MainCanvas (ConditionallyVisibleCanvas + AlwaysVisibleCanvas),
  WorldToScreenDrawCanvas (DynamicDrawCanvas: seeker, locators, target selection; gun reticle), TopPriorityCanvas.
- The HUD actor class is `LiveHUD` (BP `LiveMainHUDParent4K`). The flight HUD is NOT in the viewport (test 13 dump:
  MainFlight "in viewport: false"): it is drawn into `HUDWidgetRenderTexture` / `HUDWidgetNonGlowRenderTexture` and
  composited with a glow. Survival's layer is a normal viewport widget (no glow).
- UI scale = viewport height / 2160 (test 13: 2560x1440 -> 0.667), the same 4K reference as the HUD.
- In Survival (Mission 22's row) the mode panel is CampaignInfo_000: TIME and SCORE (+ "/32000") shown, TEAM SCORE,
  TGT and the TARGET label collapsed.
- From Lua, GetCachedGeometry reads back 0x0 for every widget (stock and ours), so on-screen positions can't be read
  that way; place from the static layout (GetDesiredSize is the next thing to try).
- `ForEachGameMode` has an empty RootPanel: the game adds the per-mode info panel (CampaignInfo / FreeFlightInfo /
  online modes) in code.

## Where things sit (design units, x,y = top-left, w x h)
| Element | Widget | Rect |
| --- | --- | --- |
| Mission info stack: TIME, SCORE, TEAM SCORE, TGT, TARGET | CampaignInfo_000 / FreeFlightInfo_000 VerticalBox_39 | 190,108, 800 wide, auto height |
| Minimap | MainFlight MIniMapCanvas | 196,1108 940x940 |
| Player state (speed/alt/weapons/damage) | WBP_HUD_SubWidgets_Parts_PlayerState_000 | 3104,1110 648x994 |
| Radio portrait (comm window) | Message_000 CanvasPanel_ComPortrait | 3224,180 420x532 |
| Event notify card | Message_000 CanvasPanel_EventNotify | 3112,298 536x360 |
| Boss / unit health bars | MainFlight UnitLifeList | 1570,500 700x60 |
| MAD indicator | MainFlight MADPanel | 1520,340 800x300 |
| Banner 1 (MISSILE ALERT, MISSION START...) | Message_000 MessageLayerOne | 1725,860 390x69 (centre 1920,894) |
| Banner 3 (RETURN TO CARRIER...) | Message_000 MessageLayerThree | 1667,1230 506x69 |
| ESM / MAD text boxes | Message_000 ESMPanel / MADPanel | 1720,1540 400x64 |
| Player name panel | Message_000 PlayerNamePanel | 1420,1614 1000x64 |
| Wingman commands | WBP_HUD_Command_Wingman_000 | bottom-left, auto size |

## Style
- Info text: font `/Game/UI/Font/UI_FontSet_ja`, typeface `HUD`, size 37, letter spacing -70, colour white (default),
  RenderOpacity 0.55. Rows are HorizontalBoxes "LABEL:" + value with 10 px right padding after the label.
  Timer: `TIME:` + `00:00:00` (TimerAndGauge, 800x36).
- Banners (MessageLayerOne/Three): text size 37, spacing -35, centred, opacity 0.55, framed by four 4 px Images with
  no brush texture (a plain white quad), opacity 0.55.
- Non-glow banner `WBP_HUD_NonGlowMessage_000`: black text (0,0,0,1) "MISSION START", size 37, outline 1, on
  `LayerTwoBackground`, inside an additive RetainerBox. No event graph, parent class plain UserWidget: Survival uses it
  as the base of its own HUD layer (its parts collapsed).
- Event notify title: size 24, colour (0.75,0.75,0.75,0.8).

## Building widgets at run time (UE4SS 3.0.1 Lua)
- `UUserWidget` and `UWidget` are `UCLASS(Abstract)`: StaticConstructObject on them is a Fatal error in a shipping
  build. Create a concrete widget-blueprint class with `WidgetBlueprintLibrary.Create(worldContext, class, pc)`.
- TextBlock, Image, CanvasPanel, ScaleBox, SizeBox, HorizontalBox, VerticalBox are concrete: StaticConstructObject
  them with the widget's WidgetTree as outer and a unique name, then `canvas:AddChildToCanvas(w)` -> CanvasPanelSlot
  (SetAnchors / SetOffsets / SetAlignment / SetAutoSize / SetPosition / SetSize).
- Text: `SetText(KismetTextLibrary:Conv_StringToText(s))` (the FText constructor scan isn't in this UE4SS log).
- Survival's layer: base widget root -> ScaleBox (ScaleToFit) -> SizeBox 3840x2160 -> CanvasPanel, so the design
  coordinates above can be used as they are at any resolution.

## Package format notes (hud_layout.py)
- Unversioned properties omit class defaults: CanvasPanelSlot offsets default (0,0,100,30), anchors (0,0),
  alignment (0,0); nested struct fields are relative to those defaults, so an explicit zero shows as a zero-mask entry.
- UE5.4 `FSlateBrush.ImageSize` (`DeprecateSlateVector2D`) and `UVRegion` (`Box2f`) are stored as raw binary
  (8 and 17 bytes), not tagged properties.
- A widget-blueprint instance inside another blueprint has its blueprint's own variables first in the property index;
  its UserWidget fields are found by trying index shifts until its `Slot` points back at the slot holding it.

## Matching the look (test 13 screenshot, 2560x1440)
- On screen the stack rows are 68 design units apart (TIME top 108, SCORE top 176), more than the widget paddings
  suggest; Survival's rows use y 244 / 312 and pitch 68.
- The HUD widgets are white; the green comes from the post-process tint (+ glow, `PostProcessHUDGlow*`). Measured text
  core sRGB (140,255,156) ~ linear (0.26,1,0.33). The exe has wide-string colour names `HUD_ColorMain`,
  `HUD_ColorText`, `HUD_ColorMainText_NonGlow`, ... and `LiveHUDColor` (not in MPC_InGame_Common_000, which holds
  Main_Green (0,1,0.27), Main_Red, Text_Ally/Enemy/Wingman/Important): where the player's HUD colour option lives is
  still to be found, so Survival's colour is a config value for now.
- The mission info text is UI_FontSet_ja's `HUD` typeface (0710_AcesSleipnirTextHUD-Regular, monospaced, slashed
  zero). A SetFont table with TypefaceFontName "HUD" still rendered the set's default proportional face; 0.7.1 writes
  the typeface into the TextBlock's own Font and copies the live PrivateScore label's Font once the panel exists.

## Survival's rows and the info key (code review F6 of 2026-10-29; the info wall 2026-10-31; not yet run in game)
The user (2026-10-29, a screenshot of a 3-player co-op HUD): "assign a hotkey like 'i' for information, say it'll open up
a hud on the screen that shows you some details, just to help clean the HUD up so that details that don't need to be seen
constantly are hidden unless the player wants to see them".
- The rows (sv_hud.lua hudBuild, CFG.hud): ROUND (y 312, WAVE n/m in a waved round), ZOLLARS (380), AIRFIELD and its bar
  (448), then the stack from 516, its shown rows one `line` (68) apart (stackRows): NEXT ROUND / the special's row,
  ALLIES, ITEMS, CO-OP. All four shown, the last is at 720: the stack ends above the minimap (MIniMapCanvas, top 1108).
  Until 2026-10-31 CO-OP had up to 4 player lines under it (all eight rows ended at 992), so a room of more than 4 showed
  three players and `+N MORE`: the user, "when more than 3 players join, you can't see what other players are doing as
  the Information Bar doesn't have enough room". The players moved to the info wall (below). The game's own SCORE /
  TARGET stay as they are.
- Always shown: ROUND / WAVE, ZOLLARS, AIRFIELD and NEXT. The info rows ALLIES, ITEMS and CO-OP only peek (below), and
  are hidden while the info wall is open. NEXT comes first so it stays put while they peek.
- Closed, an info row still shows `peek_s` (5 s, up to the next second's read) when its news changes or it comes back
  after having nothing. Each row's news is its line function's second value: ALLY.hudLine's which flights, ships and
  defences are there and the order (not their counts, health or the kills), TAC.line's the items carried and SECOND
  CHANCE (not the ECM's seconds), COOP.hudLine's who's in, a link lost (LOST) and who's DOWN by the last state their
  game sent (not health, the airfield or a state gone stale, a downed player's too: a lagging link would peek every few
  seconds). A peek waits only while the HUD is down (paused, no player aircraft or the game HUD off: the rows are read
  again the moment it's back), not for the landing menu as such: solo the STORE pauses the game, so an item bought
  there peeks after takeoff; in co-op it doesn't pause (sv_coop.lua's online-style pause), so unless AC8 turns its HUD
  off at the landing menu the peek runs there and may be over by takeoff (untested). News seen with the wall open is no
  peek once it's shut.
- The info wall (the user, 2026-10-31: "an information wall that appears in the center of the screen on a button press
  and hides on a button press. Similar to how the end of round information screen works"): the key opens and shuts a
  panel styled as the run's summary (CFG.hud.summary's fill and edge; sv_hud.lua wallBuild / wallRows / wallTick,
  CFG.hud.wall, CFG.hud.text.wall_*). Title INFORMATION, then its rows, a line (68) apart, then `PRESS I TO CLOSE`:
  - co-op (COOP.wallInfo): `CO-OP  3/24 PLAYERS`, then a line a player, the host first:
    `WAR (HOST, YOU)   F-16C   FLYING   100%`, `CRESSENDO   SU35   DOWN`, `REAPER (LOST)   NOT IN THE MISSION`
    (the aircraft: your plane's GetObjName, M.myAc, and each other player's from their hello, as on their box; the state
    from COOP.players()'s sources: your pawn, each other player's SV_CoopPeerAt state, NOT IN THE MISSION when it isn't
    fresh). Every player: from `cols_from` (9) they go in two columns, the first half left, the rest right (24 players:
    12 rows). A joiner still looking for its host: that header alone. Then an empty row.
  - `ALLIES:  <ALLY.hudLine or NONE>`, `ITEMS:  <TAC.line or NONE>`,
    `THIS RUN'S KILLS:  YOU n   ALLIES n   SHIPS n   DEFENCES n` (RUN.kills).
  - Geometry (3840 x 2160): centred on x 1920 and on y `y_mid` (1000), `top` (130) + rows x 68 + `bottom` (100) tall,
    `w` 2200 wide, or `w2` 3000 with two columns (each `col_dx` 740 off the middle, centre-justified like the summary's
    lines). 24 players: 17 rows, the panel from y 307 to 1693. Moved only when its row count or columns change. Built
    before the callout banner, which draws over it. Hidden under the run's summary (LB.show), with the whole HUD (paused,
    no plane, the game HUD off), and each level starts shut (start_open: open).
- The key: CFG.hud.info `{ enabled, key = "I", ctrl = false, start_open = false, peek_s = 5.0 }` (survival.ini
  `[hud.info]`; hud is PERSONAL in co-op, each player's own). sv_hud.lua binds it at load with RegisterKeyBind (pcall,
  no modifier, or Ctrl with ctrl); the callback (ExecuteInGameThread) only flips the open flag, and only in a run (D),
  so a press on the menus can't change the next run's HUD; hudTick opens or shuts the wall on its next pass and reads
  it at once. A release feature: not in a TEST ONLY block, so strip_test_only.py leaves it (hud_info_test.sh runs on
  stripped parts). The rows and the wall are read once a second; nothing per frame.
- UE4SS's key binds are keyboard only and don't take the key from the game: if AC8 does something on I, both happen
  ([hud.info] key picks another: a UE4SS Key name, any case). A pad button would need the runtime's input hook
  (BuildFlightInput's detour, hard rule 28): not done.
- Fallbacks: a key name UE4SS doesn't know, no RegisterKeyBind, or a bind that errors turns the key off for the session
  (the rows always shown and no wall, never hidden for good). enabled = false: the old HUD (CO-OP first, every row
  shown whenever it has something, the compact co-op row) and no wall.

Log lines:
- `hud: info key I: the info wall (players, allies, items) shown when it's pressed; the CO-OP, ALLIES and ITEMS rows
  each shown 5.0 s when it changes` (at load; `open at the start` with start_open; `Ctrl+I` with ctrl)
- `hud: info key <K> not bound (<why>): the info rows always shown, no info wall` (`'X' isn't a key name UE4SS knows:
  [hud.info] key`, `UE4SS has no key binds here`, or the bind's error)
- `hud: info wall shown (I)` / `hud: info wall hidden (I)` on each press in a run
- `hud: co-op row error <msg>`, `hud: info wall error <msg>`, `hud: info wall: co-op error <msg>` (once a level)

Offline test: `sh tools/checks/hud_info_test.sh` (79 checks, on the real sv_core, sv_config, sv_ai, sv_hud, sv_allies,
sv_tactical and sv_coop after strip_test_only, the widgets stubbed): the bind and its fallbacks, the stack's order and
its end above the minimap, each row's peeks and non-peeks, a change while paused, the press and the wall (its rows,
size, place, the corner hidden under it, the run's summary over it, a new level), co-op on the wall (a line a player
with the aircraft, 24 players in two columns, a joiner looking for its host), enabled = false, start_open.

Test checklist (in game):
1. Solo, a run's start: ROUND, ZOLLARS, AIRFIELD (and NEXT ROUND in the break) only. The log has the `hud: info key I:`
   line.
2. Solo, buy an item in the STORE: after takeoff the ITEMS row shows about 5 s, then goes. Use one (Ctrl+F1-F3): it shows
   again; an ECM burst's seconds don't keep it up. Buy WINGMEN: ALLIES shows when they're up; Ctrl+F4 shows it again.
3. Press I: the info wall in the middle of the screen at once (`hud: info wall shown (I)`), INFORMATION, ALLIES,
   ITEMS, the run's kills and PRESS I TO CLOSE; press again: gone. Does the text fit its panel at your resolution (the
   widths are estimates: 37-unit text, about 22 units a letter)? Does the game do anything on I too (a camera, a view)?
   If so, note it: [hud.info] key should default to another key.
4. Co-op (2+ players): the CO-OP row shows when someone joins, drops or is shot down, not when they land or lose health.
   Press I: `CO-OP n/max PLAYERS` and a line each, name, aircraft, FLYING / AT THE AIRFIELD / DOWN and health; with 9 or
   more, two columns and every player. Buy an item in the STORE with another player linked: does ITEMS peek after
   takeoff, or while the store is up (is Survival's HUD drawn over it there)? A downed player on a lagging link: the
   CO-OP row shouldn't keep coming back.

Untested [I]: whether a bind with no modifier still fires with Ctrl held (UE4SS's modifier match), whether AC8 binds I,
the wall's text widths in its panel, and a peek's timing around the STORE (solo the round clock stops while
paused; in co-op the game isn't paused there, so the peek may run while the store is up).
