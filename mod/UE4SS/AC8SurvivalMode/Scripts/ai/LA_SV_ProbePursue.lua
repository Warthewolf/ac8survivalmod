local LA_SV_ProbePursue = Inherit(CppObjectBase)
function LA_SV_ProbePursue:Ctor()
self:GenerateBehavior()
self:AddRootComposite("LaxSequencer", self:InstanceLaxSequencer())
self:AddTask("LaxSequencer", "SV_RollRight", self:InstanceManeuverBarrelRoll(1, 1.0, 1.0, "TargetActor", ELiveAIManeuverSpeedType.SpdRelative, 100.0, 5.0, false, 500.0))
self:AddTask("LaxSequencer", "SV_RollLeft", self:InstanceManeuverBarrelRoll(-1, 1.0, 1.0, "TargetActor", ELiveAIManeuverSpeedType.SpdRelative, 100.0, 5.0, false, 500.0))
self:AddTask("LaxSequencer", "PursuerTarget", self:InstancePursuerTarget(15.0, "TargetActor", 3.0, false, 2000.0, 20.0, false, 120.0, 3.0, 4.0, false, 60.0, 3000.0, true, true, false, FVector.New(-400.0, 0.0, 5.0)))
self:AddTask("LaxSequencer", "SetMoveAwayFromTarget", self:InstanceSetMoveAwayFromTarget("SelfActor"))
self:EndGenerateBehavior()
end
return LA_SV_ProbePursue
