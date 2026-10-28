local LA_SV_SkirmPass = Inherit(CppObjectBase)
function LA_SV_SkirmPass:Ctor()
self:GenerateBehavior()
-- The Skirmisher's attack (behaviour roadmap P1, the stand-off harasser: "can you finish a fight before the next one
-- starts?"; NLID_SV_Skirmisher's PursueTarget). It closes for a shot and breaks off the moment it has fired: the
-- pursuit sits under IsFireMissileFinished(false, abort), re-checked every frame (the stock wingmen's shape over a
-- RandomSelect), so its first missile (its long-range LAAM copy from 7 km, or its missiles from 4 km) aborts it and it
-- extends (LA_SV_SkirmExtend). It gives up after 8 s anyway, extends when you turn out of its nose cone for 2 s (a7)
-- and breaks off a head-on merge within 3 km (a11-a13), KDS blocked. The attack is a LaxSequencer of its own, so a gate
-- that fails at entry (a missile already counted, [I]) still ends in the break-off below.
self:AddRootComposite("SV_SkirmPass_Root", self:InstanceLaxSequencer())
self:AddTask("SV_SkirmPass_Root", "SP_Level", self:InstanceManeuverLevel(1.0, 1.0, "TargetActor", ELiveAIManeuverSpeedType.SpdConstant, 1750.0, 0.1, false))
self:AddComposite("SV_SkirmPass_Root", "SP_Attack", self:InstanceLaxSequencer())
self:AddDecorator("SP_Attack", "SP_NoShotYet", self:InstanceDecoratorIsFireMissileFinished(false, true))
self:AddComposite("SP_NoShotYet", "SP_Pick", self:InstanceRandomSelect())
self:AddTask("SP_Pick", "SP_Pursue", self:InstancePursuerTarget(8.0, "TargetActor", 10.0, false, 3000.0, 20.0, true, 120.0, 2.0, 8.0, true, 45.0, 3000.0, true, false, false, FVector.New(-400.0, 0.0, 5.0)))
self:AddTask("SV_SkirmPass_Root", "SP_MoveAway", self:InstanceSetMoveAwayFromTarget("SelfActor"))
self:EndGenerateBehavior()
end
return LA_SV_SkirmPass
