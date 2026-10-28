local LA_SV_LancerPass = Inherit(CppObjectBase)
function LA_SV_LancerPass:Ctor()
self:GenerateBehavior()
-- The Lancer's attack (behaviour roadmap P1, boom and zoom: "can you dodge from above?"; NLID_SV_Lancer's PursueTarget,
-- tools/re/BEHAVIOUR_DIRECTOR.md unit 5). One slashing pass and through: it dives in leading the target (a4 true, the
-- campaign aces' head-on lead pass), gives up the moment you turn out of its nose cone for 2 s (a7, the stock
-- "extend when behind" switch: it never turns with you) and breaks off a head-on merge within 2.4 km (a11-a13), KDS
-- blocked (a14). Then it blows through for 2 s at full speed and hands over to its zoom climb (LA_SV_LancerZoom, the
-- MoveAwayFromTarget slot). PursuerTarget has no speed: the airframe's own closes it (BEHAVIOUR_NATIVE_MOVE.md 2).
self:AddRootComposite("SV_Lancer_Root", self:InstanceLaxSequencer())
self:AddTask("SV_Lancer_Root", "LP_Level", self:InstanceManeuverLevel(1.0, 1.0, "TargetActor", ELiveAIManeuverSpeedType.SpdConstant, 2500.0, 0.2, false))
self:AddTask("SV_Lancer_Root", "LP_Pass", self:InstancePursuerTarget(6.0, "TargetActor", 10.0, true, 3000.0, 20.0, true, 120.0, 2.0, 6.0, true, 45.0, 2400.0, true, false, false, FVector.New(-400.0, 0.0, 5.0)))
self:AddTask("SV_Lancer_Root", "LP_Through", self:InstanceManeuverFlyStraight("TargetActor", ELiveAIManeuverSpeedType.SpdConstant, 3000.0, 2.0, false))
self:AddTask("SV_Lancer_Root", "LP_MoveAway", self:InstanceSetMoveAwayFromTarget("SelfActor"))
self:EndGenerateBehavior()
end
return LA_SV_LancerPass
