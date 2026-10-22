local LA_SV_MoveAway = Inherit(CppObjectBase)
function LA_SV_MoveAway:Ctor()
self:GenerateBehavior()
self:AddRootComposite("LaxSequencer", self:InstanceLaxSequencer())
self:AddTask("LaxSequencer", "ManeuverLevel", self:InstanceManeuverLevel(1.0, 1.0, "TargetActor", ELiveAIManeuverSpeedType.SpdConstant, 1300.0, 0.3, false))
self:AddTask("LaxSequencer", "MoveAwayFromTarget", self:InstanceMoveAwayFromTarget(1.2, "TargetActor", 1000.0, true))
self:EndGenerateBehavior()
end
return LA_SV_MoveAway
