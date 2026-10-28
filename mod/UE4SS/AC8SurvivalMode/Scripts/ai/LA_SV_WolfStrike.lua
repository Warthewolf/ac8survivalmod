local LA_SV_WolfStrike = Inherit(CppObjectBase)
function LA_SV_WolfStrike:Ctor()
self:GenerateBehavior()
-- The Wolf trap's attack (behaviour roadmap P1; NLID_SV_WolfWing's PursueTarget, the odd planes of a Wolf flight, held
-- at engagement None until the trap springs: Scripts/sv_spawn.lua WOLF). A gunfighter: a hard turn onto the target,
-- then 200 m behind it twice for 12 s with a re-acquire turn between, never giving up (a7 false) and no head-on break,
-- KDS blocked; its gun leads you (the Wolf airframes' gun rows, CFG.roles.wolf.gun_lead_s). At AI level 5 (Demon,
-- Phantom, Reaper) half its runs are LA_SV_TailChase's "Super" (a 600 km/h turn, 15 s 150 m behind, twice), so an ace
-- squadron put in a Wolf flight keeps it (the critic's P9 caveat).
self:AddRootComposite("SV_WolfStrike_Root", self:InstanceLaxSequencer())
self:AddTask("SV_WolfStrike_Root", "WS_Level", self:InstanceManeuverLevel(1.0, 1.0, "TargetActor", ELiveAIManeuverSpeedType.SpdConstant, 1500.0, 0.1, false))
self:AddComposite("SV_WolfStrike_Root", "WS_Skill", self:InstanceRandomSelect())
self:AddProbability("WS_Skill", "WS_SuperW", self:InstanceWeightProbabilityAILevel(0.0, 0.0, 0.0, 0.0, 100.0))
self:AddComposite("WS_SuperW", "WS_Super", self:InstanceLaxSequencer())
self:AddTask("WS_Super", "WS_SuperTurn", self:InstanceManeuverTurnAdvanced(3.0, 3.0, "TargetActor", ELiveAIManeuverSpeedType.SpdConstant, 600.0, 4.0, false, 500.0))
self:AddTask("WS_Super", "WS_Super1", self:InstancePursuerTarget(15.0, "TargetActor", 100.0, false, 1500.0, 20.0, false, 120.0, 3.0, 10.0, false, 60.0, 3000.0, true, false, true, FVector.New(-150.0, 0.0, 0.0)))
self:AddTask("WS_Super", "WS_SuperTurn2", self:InstanceManeuverTurnAdvanced(3.0, 3.0, "TargetActor", ELiveAIManeuverSpeedType.SpdConstant, 600.0, 4.0, false, 500.0))
self:AddTask("WS_Super", "WS_Super2", self:InstancePursuerTarget(15.0, "TargetActor", 100.0, false, 1500.0, 20.0, false, 120.0, 3.0, 10.0, false, 60.0, 3000.0, true, false, true, FVector.New(-150.0, 0.0, 0.0)))
self:AddProbability("WS_Skill", "WS_StrikeW", self:InstanceWeightProbabilityPilotRank(100.0, 100.0, 100.0, 100.0, 100.0))
self:AddComposite("WS_StrikeW", "WS_Strike", self:InstanceLaxSequencer())
self:AddTask("WS_Strike", "WS_Turn", self:InstanceManeuverTurnAdvanced(3.0, 3.0, "TargetActor", ELiveAIManeuverSpeedType.SpdConstant, 1500.0, 2.0, false, 500.0))
self:AddTask("WS_Strike", "WS_Guns1", self:InstancePursuerTarget(12.0, "TargetActor", 10.0, false, 1200.0, 20.0, false, 120.0, 3.0, 10.0, false, 60.0, 3000.0, true, false, true, FVector.New(-200.0, 0.0, 5.0)))
self:AddTask("WS_Strike", "WS_Reacquire", self:InstanceManeuverTurnAdvanced(3.0, 3.0, "TargetActor", ELiveAIManeuverSpeedType.SpdConstant, 1700.0, 1.2, false, 500.0))
self:AddTask("WS_Strike", "WS_Guns2", self:InstancePursuerTarget(12.0, "TargetActor", 10.0, false, 1200.0, 20.0, false, 120.0, 3.0, 10.0, false, 60.0, 3000.0, true, false, true, FVector.New(-200.0, 0.0, 5.0)))
self:AddTask("WS_Strike", "WS_MoveAway", self:InstanceSetMoveAwayFromTarget("SelfActor"))
self:EndGenerateBehavior()
end
return LA_SV_WolfStrike
