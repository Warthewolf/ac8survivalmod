# HUD notes (for Survival's round HUD, 2026-10-21; work paused, nothing built yet)

Tools: `tools/re/execvt.py <Class>` (vtable + Execute, slot 87, of an event-node class: class registry ->
StaticClass -> constructor -> vtable; checked on LiveReinforcementExecution = 0x1473e0ee0), `tools/re/refl.py`
(UFUNCTION params / class function lists from UE5 codegen data). These execs have no RTTI and no plain UTF-8 names:
the class registry holds `{Z_Construct_UClass, StaticClass, L"UName", &RegistrationInfo, version}` (40 bytes).

## The game's HUD widgets (stock, under /Game/Blueprints/UI/WBP/HUD4K/)
- `Campaign/SubWidgets/MissionInfo/WBP_HUD_SubWidgets_Parts_CampaignInfo_000`: the mission info panel. TGT_Box
  (TargetText, TargetInfoText, DestroyCount, QuotaCount), ScoreText, PrivateScore(Text), BorderScoreText,
  TeamScoreTitleText, VictoryScoreText, and `TimerAndGauge` (`WBP_HUD_SubWidgets_Parts_TimerAndGauge_000`: TimeText,
  RemainingTimeText). ScoreText's font: `/Game/UI/Font/UI_FontSet_ja`, typeface `HUD`, size 37, letter spacing -70,
  render opacity 0.55. Other HUD fonts: `/Game/UI/Font/0710_AcesSleipnirTextHUD-Regular`.
- `Common/SubWidgets/WBP_HUD_SubWidgets_Message_000`: banners and notices. MessageLayerOne (LayerOneText + 4 bars),
  MessageLayerThree (LayerThreeText), TimerPanel (TimerText, RemainingTimeText; anims RemainingTimerALLFadeIn/Out,
  RemainingTimerFadeIn), CanvasPanel_EventNotify (EventTitleText; anim ShowEventNotifyAnimation), CheckpointPanel,
  ScoreUpdate/Bonus texts, WeaponMessagePanel, RemainingDistancePanel.

## Event nodes
- `LiveMessageExecution` (Execute 0x1473e9870): one arg, an `EHUDMessageType` name (MISSION_START 6,
  MISSION_UPDATE 7, WAVE_UPDATE 8, MISSION_ACCOMPLISHED 9, ..._NO_SE 10, MISSION_FAILED 11, ... TIME_UP 30).
  Path: world +0x1D8 -> local players (+0x38/+0x40) -> controller (+0x30) -> HUD (controller +0x340, 0x1471e5750)
  -> HUD widget (+0x7E8) -> SetMessage 0x14726f0c0(widget, type, const FString& text). The text argument is only
  used by some types (weapon names, 54..64); the banners show fixed texts, so they can't say "ROUND 3" this way.
- `LiveCallRemoteEventExecution` (Execute 0x1473f86b0) fires an EP remote event by name; a native `SV_Event(name)`
  can do the same, so Lua could trigger stock nodes (radio, sound, timers) placed in Survival's event package:
  event object on the stack = {vtable 0x14cb68ce0, TArray<uint8> types = {0x4F}, FName name at +0x18};
  manager = 0x1470d2460(world) (a world subsystem; world = any actor's vfunc 0x188 GetWorld, e.g. the spawner);
  Dispatch 0x147421660(manager, &event, flags) with flags 0 when the event's vtable slot 9 is the default
  0x1416baca0 (it is), else 2. Find all of these by signature from the Execute's bytes, as the spawner does.
- Timers: `LiveStartTimerExecution` (Execute 0x1474074f0; args: timer flag name, bool, bool) runs an EF timer flag.
  Mission 23 starts its `Time_Limit_Timer` at Default_MissionStart. LiveDisplayRemainingExecution /
  LiveHideRemainingTimerExecution show / hide the remaining-time panel (Mission 8).
- Sounds that fit: `AKE_UI_InGame_Timer_Countdown_MissionPurpose_10sec_Play`, `..._MissionPurpose_Play`
  (Wwise event names in the exe).
