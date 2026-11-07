// SurvivalFx: Survival Mode's editor-only build tools in the AC8 template project (E:/AC8LiveProject): the LaserFx
// commandlet that rebuilds AC7's LaserInterceptor (Cascade beam, swing curve, the weapon blueprint) for AC8.
// Copied into E:/AC8LiveProject/Source/SurvivalFx by tools/laser7/build.sh. Never shipped.
using UnrealBuildTool;

public class SurvivalFx : ModuleRules
{
	public SurvivalFx(ReadOnlyTargetRules Target) : base(Target)
	{
		PCHUsage = PCHUsageMode.UseExplicitOrSharedPCHs;
		PublicDependencyModuleNames.AddRange(new string[]
		{
			"Core", "CoreUObject", "Engine", "Json", "UnrealEd", "Kismet", "KismetCompiler", "BlueprintGraph", "Live"
		});
	}
}
