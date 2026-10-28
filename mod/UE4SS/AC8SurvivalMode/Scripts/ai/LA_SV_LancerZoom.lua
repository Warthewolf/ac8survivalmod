local LA_SV_LancerZoom = Inherit(CppObjectBase)
function LA_SV_LancerZoom:Ctor()
self:GenerateBehavior()
-- The Lancer's zoom back to height after each pass (behaviour roadmap P1; NLID_SV_Lancer's MoveAwayFromTarget, after
-- LA_SV_LancerPass): wings level, a 50 deg pull-up held 3 s at full power, then an extend away from the target
-- (4 km or 4 s), about 8-10 s in all; then the state machine sends it in again from above. The climb is gated on the
-- unit's altitude band (UnitAltitudeComparison: below its top less 1 km; the Lancer flights' band tops out at 9 km,
-- tools/build_survival.py LANCER_MAX_ALT_M): near the top the gate fails, the RandomSelect's one pick does nothing and
-- the LaxSequencer goes on to the extend (tools/re/BEHAVIOUR_NATIVE_LOGIC.md 3-6).
self:AddRootComposite("SV_LancerZoom_Root", self:InstanceLaxSequencer())
self:AddTask("SV_LancerZoom_Root", "LZ_Level", self:InstanceManeuverLevel(1.0, 1.0, "TargetActor", ELiveAIManeuverSpeedType.SpdConstant, 3000.0, 0.3, false))
self:AddComposite("SV_LancerZoom_Root", "LZ_Climb", self:InstanceRandomSelect())
self:AddDecorator("LZ_Climb", "LZ_Room", self:InstanceDecoratorUnitAltitudeComparison(false, 1000.0))
self:AddComposite("LZ_Room", "LZ_ClimbSeq", self:InstanceSequencer())
self:AddTask("LZ_ClimbSeq", "LZ_Pull", self:InstanceManeuverPitch(1.0, 50.0, "TargetActor", ELiveAIManeuverSpeedType.SpdConstant, 3000.0, 2.5, false))
self:AddTask("LZ_ClimbSeq", "LZ_Hold", self:InstanceManeuverFlyStraight("TargetActor", ELiveAIManeuverSpeedType.SpdConstant, 3000.0, 3.0, false))
self:AddTask("SV_LancerZoom_Root", "LZ_Extend", self:InstanceMoveAwayFromTarget(4.0, "TargetActor", 4000.0, true))
self:EndGenerateBehavior()
end
return LA_SV_LancerZoom
