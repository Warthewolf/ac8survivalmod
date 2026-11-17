// NiagaraTemplateCommandlet: (2026-11-17, tools/stormfx) Niagara's empty emitter template, which Epic's
// CascadeToNiagaraConverter loads in AddEmptyEmitter (/Niagara/DefaultAssets/Templates/CascadeConversion/CompletelyEmpty)
// and which some UE 5.4 installs lack. Made with the emitter factory's "no default modules and renderers" (a field Python
// can't set): no modules, no renderer.
//   UnrealEditor-Cmd.exe <AC8_LIVE_PROJECT>/Live.uproject -run=NiagaraTemplate -log=<out.log>
// It never overwrites one that's there. Writes into the engine's Niagara plugin content (an addition, nothing changed).
#pragma once
#include "CoreMinimal.h"
#include "Commandlets/Commandlet.h"
#include "NiagaraTemplateCommandlet.generated.h"

UCLASS()
class UNiagaraTemplateCommandlet : public UCommandlet
{
	GENERATED_BODY()
public:
	UNiagaraTemplateCommandlet();
	virtual int32 Main(const FString& Params) override;
};
