# The game's HUD layout (reverse-engineered 2026-10-22, for Survival's own run-time HUD)

Tool: `python tools/re/hud_layout.py <zen widget pkg>...` prints a widget blueprint's tree with every slot's anchors,
offsets, alignment and the resulting rectangle on the design canvas, plus texts (default string, font, colour),
images (brush, size) and embedded widget blueprints. Pull packages first with `tools/get_stock.sh`
(the 110 HUD widgets: `build/scan/hud_wbp.txt`; full dump of all of them: `build/scan/hud_layout_all.txt`).
Run-time check: Ctrl+F9 in game (Lua 0.7.0+) writes the live HUD tree with on-screen geometry to
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
