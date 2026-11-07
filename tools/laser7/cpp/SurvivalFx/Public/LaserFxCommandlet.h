// LaserFxCommandlet: rebuilds AC7's LaserInterceptor for AC8 from the specs tools/laser7 writes.
//   UnrealEditor-Cmd.exe E:/AC8LiveProject/Live.uproject -run=LaserFx -spec=<laser7.json> -log=<out.log>
// The spec: { "root": "/Game/Mods/SurvivalMode/Laser7", "curve": {...}, "systems": [<fxspec.py system>...],
// "blueprint": { "name", "parent", "cdo": {prop: text}, "components": {comp: {prop: text}} } }.
#pragma once
#include "CoreMinimal.h"
#include "Commandlets/Commandlet.h"
#include "LaserFxCommandlet.generated.h"

UCLASS()
class ULaserFxCommandlet : public UCommandlet
{
	GENERATED_BODY()
public:
	ULaserFxCommandlet();
	virtual int32 Main(const FString& Params) override;
};
