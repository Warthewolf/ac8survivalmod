local LA_SV_WolfDrag = Inherit(CppObjectBase)
function LA_SV_WolfDrag:Ctor()
self:GenerateBehavior()
-- The Wolf bait tailed (behaviour roadmap P1, bait and trap: "will you take the bait?"; NLID_SV_WolfLead's ProvokeNear,
-- the even planes of a Wolf flight): it drags you instead of breaking. Wings level, then straight, or a lazy jink either
-- side, staying a little faster than you (speed relative to the pursuer, as stock EscapeFromPursuer_0000_CP holds it),
-- 3.5 s at most (6 s in Provoke sets the stock blackout); its escape is the stock 8 s run, so a tailed bait flies a
-- straight, readable line for ~11 s while the trap (its held odd wingmen, Scripts/sv_spawn.lua WOLF) closes. Every
-- pick moves: no gate (tools/re/BEHAVIOUR_NATIVE_LOGIC.md 3-6).
self:AddRootComposite("SV_WolfDrag_Root", self:InstanceLaxSequencer())
self:AddTask("SV_WolfDrag_Root", "WD_Level", self:InstanceManeuverLevel(1.0, 1.0, "PursuerActor", ELiveAIManeuverSpeedType.SpdRelative, 300.0, 0.5, false, 1500.0))
self:AddComposite("SV_WolfDrag_Root", "WD_Pick", self:InstanceRandomSelect())
self:AddComposite("WD_Pick", "WD_Straight", self:InstanceSequencer())
self:AddTask("WD_Straight", "WD_S_Run", self:InstanceManeuverFlyStraight("PursuerActor", ELiveAIManeuverSpeedType.SpdRelative, 300.0, 3.0, false, 1500.0))
self:AddComposite("WD_Pick", "WD_JinkRight", self:InstanceSequencer())
self:AddTask("WD_JinkRight", "WD_JR_Roll", self:InstanceManeuverRoll(1.0, 45.0, "PursuerActor", ELiveAIManeuverSpeedType.SpdRelative, 300.0, 0.3, false, 1500.0))
self:AddTask("WD_JinkRight", "WD_JR_Pitch", self:InstanceManeuverPitch(0.6, 20.0, "PursuerActor", ELiveAIManeuverSpeedType.SpdRelative, 300.0, 1.5, false, 1500.0))
self:AddTask("WD_JinkRight", "WD_JR_Level", self:InstanceManeuverLevel(1.0, 1.0, "PursuerActor", ELiveAIManeuverSpeedType.SpdRelative, 300.0, 1.0, false, 1500.0))
self:AddComposite("WD_Pick", "WD_JinkLeft", self:InstanceSequencer())
self:AddTask("WD_JinkLeft", "WD_JL_Roll", self:InstanceManeuverRoll(-1.0, 45.0, "PursuerActor", ELiveAIManeuverSpeedType.SpdRelative, 300.0, 0.3, false, 1500.0))
self:AddTask("WD_JinkLeft", "WD_JL_Pitch", self:InstanceManeuverPitch(0.6, 20.0, "PursuerActor", ELiveAIManeuverSpeedType.SpdRelative, 300.0, 1.5, false, 1500.0))
self:AddTask("WD_JinkLeft", "WD_JL_Level", self:InstanceManeuverLevel(1.0, 1.0, "PursuerActor", ELiveAIManeuverSpeedType.SpdRelative, 300.0, 1.0, false, 1500.0))
self:EndGenerateBehavior()
end
return LA_SV_WolfDrag
