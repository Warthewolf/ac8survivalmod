# Minimap (radar map) and HUD world markers: how they work, how Survival can add its own

Research of 2026-10-23 (no in-game test yet). Read HUD_LAYOUT.md / HUD_NOTES.md first: the flight HUD, minimap included,
is drawn into a render texture (`HUDWidgetRenderTexture`, with glow), not the viewport.

Legend: **[V]** verified from the exe's reflection data, the usmap, stock packages or stock EP/WD records.
**[I]** inferred (names, field lists, usage patterns), still needs a test. **[S]** speculative.
Layers: **WD/EP** = build time (tools/build_survival.py, tools/survival_events.py), **Lua** = run time
(Scripts/main.lua), **RT** = native runtime (runtime/survival_rt.c).

How the data below was read (repeatable; none of this is a repo tool yet):
- Class/struct/enum schemas: `tools/usmap.pkl` (an `usmap.Usmap`: `.structs[name] = {super, props[(idx, arraydim, name, type)]}`,
  `.enums[name]`). Load it with `tools/scripts` on sys.path.
- UFUNCTION owners and params: `python tools/re/refl.py func <Fn>` / `class <Fn>` (the class mode takes a *function* name
  and lists the functions next to it). The owning class comes from FFunctionParams.OuterFunc = Z_Construct_UClass_X, found
  in the class registry `{Z_Construct, StaticClass, L"UX", ...}` (the pointer before the name pointer).
- Property offsets: `build/research/special/scripts/propoff.py <name>...`.
- Node arguments: `tools/checks/ep_dump.py` on every stock EP in build/stock (103 files). ArgsInfo `Type` byte:
  01 AI object, 02 unit, 06 volume, 0a tag, 0c flag, 0d text key, 0e enum value, 0f int, 10 float, 11 bool.
  The TipsHash values are per argument slot; they matched no CRC/Strihash of any exe string, so slot meanings are inferred
  from values. The node classes' Execute functions sit in the protected (jumped-to 0x158xxxxxx) code: not statically readable.

---------------------------------------------------------------------------------------------------------------------
## 1. How it works

### 1a. Where the minimap lives [V]
- `ALiveHUD` (BP `LiveMainHUDParent4K`) holds the HUD widgets as reflected fields: `HudWidget`, `MainMiniMapLayerWidget`,
  `WayPointContainerWidget`, `DynamicCanvas`, `WorldToScreenDrawCanvas`, `ConditionallyVisibleCanvas`, `AlwaysVisibleCanvas`,
  `LowestPriorityCanvas`, `NonGlowWidget`, `UnitHealthList`, `OffscreenLocatorWidgets[]`, `TargetContainerManager`,
  `HUD3DUIMgr`, `AddGlowWidgetMaps`, `BattleNavigationPingDuration`, and the classes `OffscreenLocatorWidgetClass`,
  `TargetContainerActorClass`, `Texture3DUIActorClass`.
- **`ALiveHUD::AddChildToHudWidget(UObject* Content) -> UObject*`** is a UFUNCTION (owner resolved: ALiveHUD). It puts a
  widget into the HUD widget itself, i.e. into the glowing render texture like the stock HUD. Same function list:
  BeginHUDDistortion / ...OnlyRaderMap / ...OnlyCommunicationWindow / ...Lightning, EndHUDDistortion*, ResetHUDDistortion,
  SetHUDDistortionScale, SetShouldHideHUDDiration, OnBeginLanding / OnEndLanding, OnBeginAerialRefueling, ...
- `MainMiniMapLayerWidget` = `WBP_HUD_Radar_Parts_MiniMapBattleLayer_000` (class `ULiveMiniMapLayerWidget`), placed in
  MainFlight's `MIniMapCanvas` (196,1108 940x940, HUD_LAYOUT.md). It holds four `ULiveMiniMapWidget`s, one per
  `EMiniMapType` {0 MMRADAR, 1 MMREGION, 2 MMFULL, 3 MMWHOLE}:
  | field | widget | class | size in the layer |
  |---|---|---|---|
  | MiniMapSearchWidget | WBP_HUD_Radar_Parts_MiniMapBattleSearch_000 | LiveMiniMapRadarWidget (rotating radar: range circles, N/S/E/W, zoom Normal/Near/VeryNear) | 600x600, bottom-left |
  | MiniMapEnlargedWidget | ..._MiniMapBattleEnlarged_000 | LiveMiniMapScrollableWidget (scrolling map) | 940x940 |
  | MiniMapBattleWidget | ..._MiniMapBattle_000 | LiveMiniMapFullWidget (whole battle area) | 940x940 |
  | MiniMapWholeWidget | ..._MiniMapBattleWhole_000 | LiveMiniMapWholeWidget | 940x940 |
  Layer UFUNCTION `UpdateMiniMapRadarVisibility(EMiniMapType NewMiniMapType)` (+ event OnUpdateMiniMapRadarVisibility).
  Minimap UFUNCTIONs (owner ULiveMiniMapWidget): `GetMiniMapSize() -> struct`, `RefreshMiniMap()`, `OnCombatZoneUpdated()`,
  `SetRenderIconScale(float)`, `SetPlayerIconScale`, `SetRetainerBoxApplyGammaCorrection`, `SetRetainerBoxEffectsSaturation`.
- `ULiveMiniMapWidget` fields (all reflected, so readable/writable from UE4SS Lua): `MiniMapExtent` (+0x3DC),
  `bAlignCanvasToPlayer`, `bRenderCombatZone`, `bRenderWeapons`, `bRenderSelectedTargetBlinking`, `MiniMapRefreshRate`,
  `BaseCanvasPanel`, **`IconDrawCanvasPanel`** (+0x470, the canvas the icons are drawn in), `IconPool[]`
  (LiveMiniMapCanvasPanelSlot {Slot, CachedIconTexture, ...}), `CircleIconPool` (+0x430), `SearchAreaCircleIconPool`,
  `SearchAreaCutOutIconPool`, `PlayerIcon`, `CombatAreaIcon`/`CombatAreaMID`, `CachedPlayerPlane`,
  **`JammingPanel` (+0x828) / `EcmPanel` (+0x838) / `EsmEnemyPanel` / `EsmAllyPanel` / `SearchAreaPanel`** (each inside its
  own RetainerBox), `BoxVolumeWBPList` (+0x918, {TargetActor, Widget}), `BoxVolumeDashedLineWBPList`, `LandingLineWidget`,
  `ApproachWBPList`, `RailgunWBPList`, `AirExplosionWBPList`, `OutOfRange*Desc[]` (Unknown / TGT / SP / Low-, Intermediate-,
  HighScoreEnemy / Highlight: the edge-of-radar locators), `MaxOutOfRangeLocatorCount`, `MaxDisplayOutOfRangeLocatorMeters`.
  Radar widget extras: `MiniMapZoomedExtentNormal/Near/VeryNear` (Vector2D), `MiniMapZoomTimeInSecond`, `RadarCircle*`.
- Layer (`ULiveMiniMapLayerWidget`) defaults (CDO of the layer package) choose every icon: per-category textures
  (`IconTextureAir`, `...AirTGT`, `...AirEscort`, `...AirNPC`, `...AirAlly`, `...Ground*`, `...Player*`, `...OutOfRange*`,
  `...Weapon`), area textures **`IconTextureAreaCircleDashedLine / SolidLine / Fill / Gradation`** (+0x500..0x518),
  `IconTextureArea`, `IconTextureJammingArea`, `IconReturnBase`, `IconAirCarrier`, `IconTextureSonar`, `IconTexturePingRadius`,
  and the icon widget classes: `JammingAreaIcon` (+0x630) / `EcmEsmAreaIcon` (+0x638) / `CircleIcon` (+0x660) /
  `AirburstIcon` / `BoxVolumeIcon` / `BoxVolumeDashedLineIcon` / `BoxVolumeReturnLineIcon` / `LandingLineIcon` /
  `ApproachIcon`; plus `PingTimings` (ELiveRadarPingTimingType -> {Timings[], RipplesNum, RipplesInterval, IsScaleDown}),
  `RadarPings[]` / `AddRadarPings[]` (LiveRadarPing {ObjectToPing, PingPosition, PingType, bShowContainerName, bIsEnemy,
  TimingType}), `ApproachObjects[]`, `bIsEnemyIconGrow`.. `bIsAllyIconGrow`, `AreaInsideAlpha` 0.5.
  The layer package imports these widget classes: WBP_HUD_Radar_ECM_ESM_000, _Jamming_000, _DangerZone_000, _Approach_000,
  _LandingLine_000, _ReturnLine_000, _DashedLine_000, _Airburst_000, _Quadcopter_000, _Railgun_*; textures under
  /Game/UI/Texture/HUD/Radar/ (T_Icon_Radar_AreaCircleLine/DashedLine/Gradation/LineBokashi_000, T_Icon_Radar_JammingArea_000,
  T_Icon_Radar_PingCircle_000, T_HUD_Radar_AreaCircleLineL_001/002, ...). Which class field takes which import is [I].

### 1b. The radar icon widgets [V]
| widget (Blueprints/UI/WBP/HUD4K/Common/Radar/) | parent class | content |
|---|---|---|
| WBP_HUD_Radar_ECM_ESM_000 | LiveMinimapCommonIconWidget (anims `In`, `Out`) | 550x550 canvas, Image `Jamming` 600x600 centred, brush = material **M_UI_HUD_Radar_Jamming_002** |
| WBP_HUD_Radar_Jamming_000 | LiveMinimapCommonIconWidget | same layout and material |
| WBP_HUD_Radar_DangerZone_000 | UserWidget | 300x300 canvas, Image `DangerZone` with no brush (set in code) |
| WBP_HUD_Radar_Approach_000 | UserWidget | three stacked chevrons T_Icon_Radar_Approach_000 (32x28) |
| WBP_HUD_Radar_LandingLine_000 / _ReturnLine_000 / _DashedLine_000 | UserWidget | one line image (32x224 / 256x28 / 256x8) |
`ELiveMinimapCommonIconType` {Railgun, DiffusionRailgun, Jamming, ECMESM}: the common-icon widgets are the weapon-driven
areas (railgun lines, jamming circle, ECM/ESM circle).

### 1c. What puts things on the radar
1. **Game objects** [V fields / I behaviour]: every AI object is an icon chosen by category (air/ground/sea), faction,
   `TargetMarkType` and `UnidentifiedType`. `ELiveTargetMarkType` {0 None, 1 TGT, 2 SP, 3 Attention, 4 Protected,
   5 TGT_Attention, 6 CIVIL}. Stock use: TGT on mission targets (104 WD objects, 238 LiveSetCommonAttribute records),
   Attention on escorts (M006 LCACs, M007 CH-47, M013 runway, M022 shuttle: the `...Escort` icons), Protected on objects
   you must not kill (M007 Il-76s, M019 rockets). `ELiveUnidentifiedType` {None, Unknown, Disguise, Enemy, Ally, Wingman}
   (Unknown = the `T_Icon_Radar_AirUnknown_000` "?" icon). TGT/SP/Unknown/Highlight objects out of radar range get an
   edge locator (OutOfRange*Desc).
2. **Volumes** (`ALiveVolume.DrawType` +0x308, from the WD desc's `DrawType` +0x38) [V data / I drawing]:
   `ELiveVolumeDrawType` {0 None, 1 SolidLine, 2 DashedLine, 3 Fill, 4 WarningArea, 5 SafeArea, 6 SearchArea, 7 ReturnLine}.
   Boxes draw edges chosen by `bDrawLineTop/Bottom/Right/Left` (BoxVolumeIcon / DashedLine / ReturnLine widgets). Stock drawn
   boxes: return lines (M008 SupplyLine_0/1, M023 Phase03_ReturnLine0, M024 Volume_ReturnBase_0, M025_2 BOX_RTB0, M026
   Box_Return_0), Fill (M025_2 Ground_Box00_01_22..25), DashedLine (M010 PhaseNClear boxes, M006 Ally_Escape_Line_0),
   SolidLine (M022 VolumeBox_PlayerN/S_0 via Debug_VisibleBox). **No stock cylinder or sphere has a DrawType** (all 41
   WD cylinders/spheres scanned), so circle areas from volumes are unproven, although the layer has the four
   AreaCircle textures and a `CircleIcon` class.
   Volumes can follow an AI object: `AttachParentAIObjectName` (M019 jamming cylinders on the airships, M023 Celaeno
   areas, M030 Edrne rings 1.2-20 km, M022 VolumeBox_PlayerN/S on dummies) [V].
3. **Electronic weapons** (ECM / ESM / lock-on jamming) [V data / I drawing]: `ULiveWeaponToRadarmapAcceseManager` (world
   subsystem) + `ILiveWeaponToRadarmapInterface` / `ILiveWeaponMiniMapInterface`; the minimap shows the area with the
   ECM_ESM / Jamming widget in EcmPanel / JammingPanel / EsmEnemyPanel / EsmAllyPanel. The E-18G's pod (DT_NPC_FCS row
   `NPC_FCS_ECM000`: FCS BP_FCS_ECM_00 -> weapon **BP_wp_ecm_a0**, class `LiveElectronicSupportMeasures`):
   `SupportEffectRangeMeter = 3200`, `JammingEffectRangeMeter = 3200`, `LifeTime = 15 s`, `FCSActivationDist 500000`;
   FCS row: CaptureDistance 6000 m, ActivationTime 2 s, TriggeringTime 15 s, ShotIntervalTime 15 s, **RestingTime 30 s**,
   MagazineCapacity 10. So the stock ECM ring is ~3.2 km and (inferred) is up ~15 s out of every ~45 s, only while a target
   is within 6 km. `LiveElectronicJamming` (lock-on jammer, BP_wp_lockonJamming_*) has `EffectRangeMeter`,
   `IconScaleInTime`, `MySupport_JammingIconColorId`. MINDRIPPER already carries NPC_FCS_ECM000 (Lua 0.35.6); no test
   note says whether the ring was seen.
4. **Pings and navigation** [V signatures / I behaviour]: `LiveRadarPing` entries on the layer (ripples, timings per
   `ELiveRadarPingTimingType` {None, Enemy, Ally, Loop, Single, Double, Triple, Quadruple}). Fed by the
   `LiveBattleNavigationExecution` node and the LiveBlueprintLibrary pings (section 1f).
5. **Approach chevrons**: `LiveRadarMapApproachActiveExecution` adds an AI object to ApproachObjects -> ApproachIcon
   (M008: the tunnel-entrance dummies `dumy_EB_Obj01_Ground0_tunnel_N`, AI_Dummy_Ground, rotated to the entrance).
6. **Landing**: `ALiveControlTowerBase.bShowMinimapLandingPosition` (reflected bool) and `LandingNavigationLine[]`;
   the minimap's `LandingLineWidget`, layer `LandingLineMinDistaneMeter` 1300; `IconReturnBase` / `IconAirCarrier`.
7. **Combat zone**: WD `CombatZoneDescList` (Survival has Mission 22's: commit 712420c), `CombatZoneAreaBrush`,
   `bRenderCombatZone`. Radar noise: `LiveStart/StopHUDRaderMapNoiseExecution` (already used by the Anomaly).

### 1d. HUD world markers [V fields / I behaviour]
- **Target boxes** are 3D billboard actors: `ALiveTargetContainerActor` (BP `ChronicleTargetContainerActorBP_C`), one per
  target, pooled by `ULiveTargetContainerManager` (`TargetContainers: TMap<object, actor>`, `ContainerPool`). Parts:
  ContainerBox, EscortBillboardImage, Emblem, Clock/AntiClock TargetPins, StarStatus, Supplies, SimpleRadio Attack/Relief,
  HP gauge + slider, texts `AllianceText`, `DistanceText`, `ObjectTypeText`, `ObjectCallsignText`, `GamerTagText`,
  `NextTargetText`, each with a material instance (`ContainerBoxMaterialInst`, `EscortMaterialInst`, `HPGaugeMaterialInst`,
  `...TextMaterialInst`, ...).
- Box on/off: `ALiveAIGameObject.bShowHUDBox` (reflected), WD `LiveAIObjectDesc.bShowHUDBox`, `LiveChildActorComponent.
  bIsShowHUDBoxChildActor`, `LiveDeadBatteryBehaviorComponent.bHideHUDBox`.
- Labels: `ObjectTypeText` = the model row's `GameObjectDisplayName01`; `ObjectCallsignText` = `GameObjectDisplayName02`
  (DT_NPC row, or WD `GameObjectDisplayNameID02` +0x70, shown for allies when `bShowCallSignForAlly`). Texts are string-table
  keys; Survival already defines its own keys at run time with `SV_SetText` (SV_Shuttle_Name, SV_Ace_*, SV_Sqn_*).
- **Offscreen arrows**: `ULiveLocatorWidget` (WBP_HUD_DynamicWidget_Parts_Locator_000: `ArrowTexture`, `ArrowScale`,
  `EnemiesDrawCount`, `TargetPinsMaterial`, `LocatorDistanceSettings`) for targets; `ULiveOffscreenLocatorWidget`
  (WBP_HUD_Locator_Wingman_000/001) for wingmen; HUD settings `LocatorOffscreen*`, `EscortOffscreenArrowScale`,
  `EscortLocatorLimitInMeter`.
- **Waypoint marker**: `ULiveWayPointContainerWidget` (WBP_HUD_Container_WayPoint_000: `Text_Body` distance text, size 28,
  over `WayPoint_Icon` 128x64; fields `Object` (weak), `WayPointPanel`, `TextBody`, `WayPointIcon`, `PosMargin`). The HUD
  has one (`ALiveHUD.WayPointContainerWidget`), so one waypoint at a time [I].
- **Unit health bars** (UnitLifeList, 1570,500), **remaining-distance panel** (Message_000 RemainingDistancePanel),
  wingman locator/box styles (`ELiveWingmanHUDForceDisplay` {None, SolidLine, DottedLine, Hidden}).

### 1e. Event nodes (argument layouts from stock records) [V layout / I meaning]
| node | args | stock use |
|---|---|---|
| **LiveSetCommonAttribute** | {02 unit} {01 object} {0a tag} {11 b3} {11 b4} {0e **ELiveTargetMarkType**} {0e ident: None/Expose/Unknown/Enemy/Ally} {11 b7} | 1669 records, 20 missions. Mark None = leave the mark. Common pairs b3/b4 = true/false (437, "activate", with TGT 225x) and false/true (466, "deactivate"): probably show-HUD / invincible [I] |
| **LiveSetVolumeAttributeException** | {11 player collision} {11 NPC collision} {06 volume} {0a volume tag} {0e **ELiveVolumeDrawType**} | 89 records. Bool meanings match the WD descs' bEnableCollisionPlayer/NPC [I]; M025_2 shows/hides Fill boxes and BOX_RTB0 by toggling arg0 [I] |
| LiveSetCylinderTransformExecution | {06 cylinder} {0a tag} {11} {10 1.0} {11} {10 1.0} {10 0.0} | M015 Green_Sotoa_Event_0 only. Probably resize/move a cylinder [S] |
| **LiveRadarMapApproachActiveExecution** | {01 AI object} {11 on} | M008 x35 (tunnels) |
| LiveRadarMapSearchAreaActiveException | unknown (no stock record) | none |
| **LiveWayPointContainerExecution** | {01 AI object} {11 on} | M015 x10 (+M027); objects `Phase01_WayPoint_0_N` = NPC `AI_Dummy_rel_Plane`, bShowHUDBox, invincible from AI, bIsAttackTargetsException |
| **LiveBattleNavigationExecution** | {0a tag} {02 unit} {0e ping timing Single/Double/Triple/Quadruple} {11 force switch to battle map} | 338 records, 8 missions |
| **LiveSetGameObjectDisplayName** | {01 object} {02 unit} {0a tag} {0e DISPLAYNAME_01/_02} {0d text key} | 66 records (callsigns, "Airbase", "Unknown") |
| LiveSetUnidentifiedTypeExecution | {01 object} {02 unit} {0a tag} {11} {0e ELiveUnidentifiedType} | M015, M028 |
| LiveUnitHealthDisplaySwitch | {02 unit} {0e ELiveDisplayUnitHealthType All/HUDOnly/UIOnly} {11 show} {11 ?} | M006 LCACs, M025_2 |
| LiveRemainingDistanceExecution | {01 mover} {01 goal object} {11 show} | M010 landing ship `rikusen0` -> distance dummies; M030 |
| LiveWingmanHUDLocatorForceDisplay / ...ContainerForceDisplay | {01 wingman} {0e None/SolidLine/DottedLine(/Hidden)} | 49 / 48 records |
| LiveStartHUDRaderMapNoiseExecution | {10} {10} {10} (M015: 4/3/6, 5/5/8) | Survival's Anomaly |
| LiveStartCelaenoJumming | {01 object} | M023 (Celaeno radome) |
Volume triggers (EventType 0x3f VolumeEvent / 0x40 BoxVolumeEvent: {06 volume} {0a tag} {0e Enter/Exit} {0e Any/AnyPlayer/
LocalPlayer} {01 object} {02 unit} ...) and `LiveIsInVolumeStatement` detect who is inside.

### 1f. Reflected functions and fields for Lua [V signature / I behaviour]
- `/Script/Live.Default__LiveBlueprintLibrary` (owner resolved from the exe):
  `PingObjectOnRadar(APlayerController InPlayerController, UObject ObjectToPing, ELivePingType InPingType, bool ShowContainerName)`,
  `PingObjectsOnRadar(PC, TArray ObjectsToPing, ELivePingType, bool)`, `PingPositionOnRadar(PC, FVector PingPosition,
  ELivePingType)`, `BattleNavigation(UObject AIObjectToPing, bool bForciblySWitchToBattleMap, int BattleNavigationID)`,
  `BattleNavigationUnit(Unit, bool, int)`, `BattleNavigationUnitList(TArray, bool, int)`, `FindAIGameObjectByWDName(FName
  WDName, UObject Target) -> object`, `GetActorsInVolume(s)`, `IsFreeFlight`. `ELivePingType` {PING_ATTACK, PING_HELP,
  PING_ALLY, PING_ENEMY, PING_DEFAULT}. (The pings come from online mode; offline effect unknown.)
- `ALiveHUD:AddChildToHudWidget(widget)`; `ALiveHUD.MainMiniMapLayerWidget`, `.WayPointContainerWidget`, `.TargetContainerManager`.
- Minimap: `LiveMiniMapWidget.IconDrawCanvasPanel / EcmPanel / JammingPanel / MiniMapExtent / bAlignCanvasToPlayer /
  CachedPlayerPlane`, `GetMiniMapSize()`, layer `RadarPings / AddRadarPings` (writable arrays of LiveRadarPing).
- Objects: `LiveAIGameObject.bShowHUDBox`, `.UnidentifiedType`, `.BriefingDisplayNameID`. (TargetMarkType is *not* a
  reflected field of the object, only of the WD desc +0x68 and LiveAIObjectCheckpointStatus.)
- Volumes: `LiveVolume.DrawType`, `bEnableCollision`, `bTestPlayer`, `bTestEnemy`, `InsideGameObjects`;
  `LiveCylinderVolume.Radius / HalfHeight / bEternalHeight`.
- ECM: `LiveElectronicSupportMeasures.EffectRangeMeter / SupportEffectRangeMeter / JammingEffectRangeMeter / bJammingEnable /
  bSupportEnable / IconScaleInTime`; `LiveElectronicJamming.EffectRangeMeter`.
- Airfield: `LiveControlTowerBase.bShowMinimapLandingPosition` (Survival's tower: BP_ControlTower_AirPort_Mission022_C).

### 1g. World-data AI object desc fields that change markers [V offsets]
`FLiveAIObjectDesc`: MissionNpcID +0x14, SpawnPoint +0x38, **TargetMarkType +0x68**, bShowHUDBox, bShowCallSignForAlly,
**GameObjectDisplayNameID02 +0x70**, bIsTgtInBriefing, bIsAttackTargetsException, Tags, AttachParentAIObjectName.
Hard rule 15 (MissionNpcID set before spawning takes effect) suggests the same works for TargetMarkType / DisplayNameID02
written before SV_Spawn [I]. Other WD lists: `MarkActorDescList` (LiveMarkActorDescV001 {Location, AttachParent}) are
invisible position markers for teleports/moves, not HUD marks [V data].

---------------------------------------------------------------------------------------------------------------------
## 2. Ways Survival can add markers, ranked (best first)

1. **TargetMarkType through LiveSetCommonAttribute** (EP + Lua). Build: `foreign_template` a stock record (e.g. an M009
   TGT one), `execute` it under `RE_SV_MarkTGT_<x>` with arg 1 (object) or arg 2 (tag) set to Survival's objects and arg 5 =
   TGT / Attention / SP / Protected; Lua fires it with `SV_Event`. Gives the stock red TGT icon, TGT box, edge-of-radar and
   offscreen arrows, all in the glowing HUD. Also usable on tags so it covers any spawn. Cheapest, most "stock" result.
   Alternative without EP records: a native `SV_SetMark(unit, type)` writing desc +0x68 before SV_Spawn (RT, [I]).
2. **Volumes with a DrawType** (WD + EP, or Lua). Build: add WD box/cylinder descs (deep copies of Survival's M22
   descs) with DrawType, edges, Tags and optional AttachParentAIObjectName; switch them with LiveSetVolumeAttributeException
   records fired by SV_Event. Boxes are proven by stock missions; cylinders need test T2. Lua alternative on the existing
   level: set `LiveVolume.DrawType` (and `Radius`, location) on a volume actor directly.
3. **The ECM/ESM ring** (WD/DT + Lua). Give the object an ECM pod FCS row (already on MINDRIPPER). Tune with Survival's own
   DT_NPC_FCS copy (RestingTime 0, TriggeringTime/ShotInterval = LifeTime for a continuous ring) and/or Lua on the live
   weapon actor (`FindAllOf("BP_wp_ecm_a0_C")`: SupportEffectRangeMeter / JammingEffectRangeMeter). Side effect: it jams
   the player's missiles (wanted for the Anomaly).
4. **Waypoint / approach / distance nodes** (WD dummy + EP). Place an invincible `AI_Dummy_rel_Plane` / `AI_Dummy_Ground`
   object (copy M015 `Phase01_WayPoint_0_0` / M008 tunnel dummy entries into a Survival unit) and fire
   LiveWayPointContainerExecution (on-screen marker with distance), LiveRadarMapApproachActiveExecution (radar chevrons),
   LiveRemainingDistanceExecution (distance panel). SV_Spawn can move the dummy unit anywhere first.
5. **Labels**: `GameObjectDisplayNameID02` keys in DT rows (done for aces/shuttle) or LiveSetGameObjectDisplayName records
   (mid-round relabel), text set with SV_SetText. LiveSetUnidentifiedTypeExecution for "?" contacts (stealth wing, guards).
6. **Lua widgets inside the stock minimap** (Lua only). Create a stock icon widget (WBP_HUD_Radar_ECM_ESM_000 /
   _DangerZone_000 / _Approach_000 class via MakeSoftObjectPath -> LoadAsset_Blocking, hard rule 9) or Survival's own
   Image, add it to the active LiveMiniMapWidget's `EcmPanel` / `IconDrawCanvasPanel` (AddChildToCanvas), and place it every
   tick from world coordinates (calibrate with T6). Unlimited shapes and colours, glow included; needs per-mode math and
   re-adding after each level load. Fallback: draw in Survival's viewport layer over the minimap rect (no glow, no clip).
7. **Pings** (Lua): `LiveBlueprintLibrary:PingPositionOnRadar(pc, pos, PING_ATTACK)` for "here" pulses (landing zones,
   portal), `BattleNavigation(obj, false, id)` / LiveBattleNavigationExecution for the stock "look here" ping on a unit.
8. **Lua HUD arrow of Survival's own** (Lua): `GameplayStatics.ProjectWorldLocationToScreen` + an arrow Image at the
   screen edge in Survival's layer. Fully controllable; no glow. Use only if 1/4 don't fit.
9. **Target-box restyling** [S]: through `TargetContainerManager.TargetContainers[obj]` -> the container actor's material
   instances (SetVectorParameterValue) or texts. The game rewrites them each update and UE4SS 3.0.1's TMap access is shaky;
   last resort.

---------------------------------------------------------------------------------------------------------------------
## 3. Recommended designs

### 3a. Boss danger ring (MINDRIPPER's 3 km control-inversion field)
1. Keep the ECM pod (it is the "ECM area" the user asked for) and make it match the field: either set
   `CFG.specials.anomaly.field_km = 3.2` (the pod's stock 3200 m), or set the live pod's SupportEffectRangeMeter /
   JammingEffectRangeMeter to field_km*1000 from Lua when it appears (T3 tells which field sizes the ring).
2. Make it continuous: a Survival FCS row copy of NPC_FCS_ECM000 (RestingTime 0, TriggeringTime = ShotIntervalTime =
   LifeTime 15, high MagazineCapacity, CaptureDistance >= 20000 m so it is up before you are near), named in MINDRIPPER's
   SVX weapon list (build: DT_SV_* rows added at the main menu, as the other SVX rows).
3. Backup if the ECM ring can't be held steady: a WD cylinder `SV_Anomaly_Field` (RadiusInMeter = field, tall
   HalfHeight, DrawType WarningArea or SolidLine, AttachParentAIObjectName = MINDRIPPER's AI object, collision player on),
   shown/hidden by LiveSetVolumeAttributeException in RE_SV_AnomalyFieldOn/Off; as a bonus its VolumeEvent Enter/Exit
   could drive the inversion instead of Lua distance checks. Needs T2.
4. Also: LiveSetCommonAttribute TGT on MINDRIPPER at arrival (edge arrow + TGT box), LiveUnitHealthDisplaySwitch for its
   HP bar, ring removed on the kill (RE_SV_AnomalyEnd).

### 3b. Beach landing zones (amphibious assault)
- Per zone a WD box desc on the beach (`ExtentsInMeter` ~ beach size, Rotation to the shoreline, DrawType Fill, Tags
  `SV_Beach`, collision NPC on). LiveSetVolumeAttributeException {false, true, -, SV_Beach tag, Fill} at round start shows all
  of them (if the first bool turns out to be "visible" rather than player collision, use true); per-zone records hide a zone
  when it is taken. The BoxVolumeEvent trigger (type 0x40, tag SV_Beach, Enter, Any,
  object = landing craft) tells the EP/Lua that a craft landed.
- Landing craft: TargetMarkType Attention (escort icons) with LiveSetCommonAttribute, health bars with
  LiveUnitHealthDisplaySwitch (M006's LCAC pattern), and LiveRemainingDistanceExecution from the lead craft to a beach dummy
  (M010's `rikusen0` pattern) for a "distance to beach" readout.
- Optional radar chevrons pointing in from the sea: a ground dummy per beach rotated toward the shore +
  LiveRadarMapApproachActiveExecution (M008's tunnel pattern).

### 3c. Objective arrow
- Objects (boss, shuttle, bombers): LiveSetCommonAttribute TGT (or Attention for things to protect). The game then draws
  the offscreen arrow on the HUD and the out-of-range locator on the radar itself; nothing to build in Lua.
- Places (beach, portal, airfield): one movable waypoint dummy unit (`SV_Unit_Waypoint`, one `AI_Dummy_rel_Plane` object,
  bShowHUDBox on, invincible, bIsAttackTargetsException), SV_Spawn it to the spot, `RE_SV_WaypointOn/Off` ->
  LiveWayPointContainerExecution {dummy, true/false}. One active waypoint at a time. Add a PingPositionOnRadar pulse when it
  moves.
- Airfield "open": set the tower's `bShowMinimapLandingPosition` during intermissions (T7); or the waypoint dummy on the
  runway; the airfield callsign key via LiveSetGameObjectDisplayName (M013 uses ContainerGround_Name_Airbase).

---------------------------------------------------------------------------------------------------------------------
## 4. In-game tests (each a debug key or a log line; T1-T3 first)
| # | test | layer | answers |
|---|---|---|---|
| T1 | Anomaly round (Ctrl+F11): log `FindAllOf("BP_wp_ecm_a0_C")` every second with SupportEffectRangeMeter / JammingEffectRangeMeter / EffectRangeMeter / LifeTime; watch the radar | Lua | is the ECM ring drawn, how long it stays, which field holds the radius |
| T2 | In Survival's level: find the LiveCylinderVolume with Radius ~10000 m (Cylinder_AreaB_Notify_rityaku0 at the airfield, 1602782 / -432456) and set DrawType 1, then 3, then 4/5; same on LiveBoxVolume VolumeBox_LandingArea1 with 3 | Lua | do cylinders draw circles; how Fill / WarningArea / SafeArea look; does a run-time DrawType change redraw |
| T3 | T2's cylinder: `K2_SetActorLocation` it onto the player every tick | Lua | does a drawn circle follow its actor (moving danger ring without WD attach) |
| T4 | Fire a LiveSetCommonAttribute TGT record on one Survival flight (new RE_ record) | EP+Lua | TGT icon/box/offscreen arrow; then log b3/b4 meaning by flipping them |
| T5 | `PingPositionOnRadar(pc, airfield, PING_ATTACK)`, `PingObjectOnRadar(pc, MINDRIPPER, PING_ENEMY, true)`, `BattleNavigation(obj, false, 0)` | Lua | do the online pings work offline |
| T6 | Read each LiveMiniMapWidget's MiniMapExtent, GetMiniMapSize(), bAlignCanvasToPlayer, visibility per minimap mode; add an Image to the visible one's IconDrawCanvasPanel at the projected airfield position and compare with the stock airfield icon | Lua | the world->minimap formula for design 6; whether added children survive RefreshMiniMap |
| T7 | Toggle the airfield tower's `bShowMinimapLandingPosition` | Lua | does a landing marker/line appear |
| T8 | `hud:AddChildToHudWidget(w)` with a TextBlock | Lua | Survival text in the glowing HUD (alternative to the viewport layer) |
| T9 | Waypoint dummy + LiveWayPointContainerExecution | WD+EP | marker look, distance text, offscreen behaviour |
| T10 | Write desc +0x68 = 1 before SV_Spawn (RT) | RT | per-spawn TGT mark without EP records |
