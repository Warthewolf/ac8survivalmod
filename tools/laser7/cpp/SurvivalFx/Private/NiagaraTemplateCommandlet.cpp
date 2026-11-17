// NiagaraTemplateCommandlet.cpp: see NiagaraTemplateCommandlet.h and tools/stormfx/build.sh.
#include "NiagaraTemplateCommandlet.h"
#include "NiagaraEmitter.h"
#include "NiagaraEmitterFactoryNew.h"
#include "Misc/FileHelper.h"
#include "Misc/PackageName.h"
#include "UObject/Package.h"
#include "UObject/SavePackage.h"

UNiagaraTemplateCommandlet::UNiagaraTemplateCommandlet()
{
	IsClient = false;
	IsEditor = true;
	IsServer = false;
	LogToConsole = true;
}

int32 UNiagaraTemplateCommandlet::Main(const FString& Params)
{
	FString LogPath;
	FParse::Value(*Params, TEXT("log="), LogPath);
	FString Out;
	auto Say = [&Out](const FString& S) { Out += S + TEXT("\n"); UE_LOG(LogTemp, Display, TEXT("NiagaraTemplate: %s"), *S); };
	const FString Path = TEXT("/Niagara/DefaultAssets/Templates/CascadeConversion/CompletelyEmpty");
	int32 Rc = 0;
	if (FPackageName::DoesPackageExist(Path))
	{
		Say(TEXT("there already: ") + Path);
	}
	else
	{
		UPackage* Pkg = CreatePackage(*Path);
		UNiagaraEmitterFactoryNew* F = NewObject<UNiagaraEmitterFactoryNew>();
		F->EmitterToCopy = nullptr;
		F->bUseInheritance = false;
		F->bAddDefaultModulesAndRenderersToEmptyEmitter = false;   // (no modules, no renderer: the converter's empty start)
		UFactory* Base = F;
		UObject* Made = Base->FactoryCreateNew(UNiagaraEmitter::StaticClass(), Pkg, FName(TEXT("CompletelyEmpty")),
			RF_Public | RF_Standalone | RF_Transactional, nullptr, GWarn);
		UNiagaraEmitter* E = Cast<UNiagaraEmitter>(Made);
		if (!E)
		{
			Say(TEXT("ERROR the emitter wasn't made"));
			Rc = 1;
		}
		else
		{
			const FString File = FPackageName::LongPackageNameToFilename(Path, FPackageName::GetAssetPackageExtension());
			FSavePackageArgs Args;
			Args.TopLevelFlags = RF_Public | RF_Standalone;
			const bool Ok = UPackage::SavePackage(Pkg, E, *File, Args);
			Say(FString::Printf(TEXT("made %s (no modules, no renderer): %s, %s"), *Path, *File, Ok ? TEXT("saved") : TEXT("NOT saved")));
			if (!Ok) Rc = 1;
		}
	}
	Say(FString::Printf(TEXT("done (%d)"), Rc));
	if (!LogPath.IsEmpty()) FFileHelper::SaveStringToFile(Out, *LogPath);
	return Rc;
}
