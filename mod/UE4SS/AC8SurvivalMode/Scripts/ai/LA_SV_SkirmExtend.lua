local LA_SV_SkirmExtend = Inherit(CppObjectBase)
function LA_SV_SkirmExtend:Ctor()
self:GenerateBehavior()
-- The Skirmisher's extend after each shot (behaviour roadmap P1; NLID_SV_Skirmisher's MoveAwayFromTarget): the stock
-- MoveAwayFromTarget_0201's long extend, out to 4.5 km (7.5 s at most), then back to the middle of its altitude band
-- (5 s), so it comes in again from range; about 12 s between shots, where Survival's duelists break 1.5 s.
self:AddRootComposite("SV_SkirmExtend_Root", self:InstanceLaxSequencer())
self:AddTask("SV_SkirmExtend_Root", "SE_Level", self:InstanceManeuverLevel(1.0, 1.0, "TargetActor", ELiveAIManeuverSpeedType.SpdConstant, 1500.0, 0.2, false))
self:AddTask("SV_SkirmExtend_Root", "SE_Extend", self:InstanceMoveAwayFromTarget(7.5, "TargetActor", 4500.0, true))
self:AddTask("SV_SkirmExtend_Root", "SE_Altitude", self:InstanceMoveCenterAltitude(5.0, 250.0, true))
self:EndGenerateBehavior()
end
return LA_SV_SkirmExtend
