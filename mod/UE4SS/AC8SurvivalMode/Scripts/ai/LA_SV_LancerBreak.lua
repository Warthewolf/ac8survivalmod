local LA_SV_LancerBreak = Inherit(CppObjectBase)
function LA_SV_LancerBreak:Ctor()
self:GenerateBehavior()
-- The Lancer tailed (behaviour roadmap P1; NLID_SV_Lancer's ProvokeNear and ProvokeMid): it never turns with you. It
-- runs: wings level and 1 s straight at full power, then a 3.5 G 180 deg reversal either side, the campaign aces' far
-- provoke (stock LA_Provoke_0400_l) with a shorter turn, 4.7 s in all (6 s in Provoke sets the stock blackout). Every
-- pick moves: no gate (tools/re/BEHAVIOUR_NATIVE_LOGIC.md 3-6). After it the Provoke dispatcher hands it to its escape.
self:AddRootComposite("SV_LancerBreak_Root", self:InstanceRandomSelect())
self:AddComposite("SV_LancerBreak_Root", "LB_Right", self:InstanceSequencer())
self:AddTask("LB_Right", "LB_R_Level", self:InstanceManeuverLevel(1.0, 1.0, "PursuerActor", ELiveAIManeuverSpeedType.SpdConstant, 4000.0, 0.2, false))
self:AddTask("LB_Right", "LB_R_Run", self:InstanceManeuverFlyStraight("PursuerActor", ELiveAIManeuverSpeedType.SpdConstant, 4000.0, 1.0, false))
self:AddTask("LB_Right", "LB_R_Turn", self:InstanceManeuverTurnNormal(3.5, 180.0, 1.5, 90.0, "PursuerActor", ELiveAIManeuverSpeedType.SpdConstant, 4000.0, 3.5, false))
self:AddComposite("SV_LancerBreak_Root", "LB_Left", self:InstanceSequencer())
self:AddTask("LB_Left", "LB_L_Level", self:InstanceManeuverLevel(1.0, 1.0, "PursuerActor", ELiveAIManeuverSpeedType.SpdConstant, 4000.0, 0.2, false))
self:AddTask("LB_Left", "LB_L_Run", self:InstanceManeuverFlyStraight("PursuerActor", ELiveAIManeuverSpeedType.SpdConstant, 4000.0, 1.0, false))
self:AddTask("LB_Left", "LB_L_Turn", self:InstanceManeuverTurnNormal(3.5, 180.0, 1.5, -90.0, "PursuerActor", ELiveAIManeuverSpeedType.SpdConstant, 4000.0, 3.5, false))
self:EndGenerateBehavior()
end
return LA_SV_LancerBreak
