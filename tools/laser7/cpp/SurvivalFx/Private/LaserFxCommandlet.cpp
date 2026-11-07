// LaserFxCommandlet.cpp: see LaserFxCommandlet.h and tools/laser7/README.md.
#include "LaserFxCommandlet.h"
#include "Particles/ParticleSystem.h"
#include "Particles/ParticleEmitter.h"
#include "Particles/ParticleSpriteEmitter.h"
#include "Particles/ParticleLODLevel.h"
#include "Particles/ParticleModule.h"
#include "Particles/ParticleModuleRequired.h"
#include "Particles/Spawn/ParticleModuleSpawn.h"
#include "Particles/TypeData/ParticleModuleTypeDataBase.h"
#include "Particles/ParticleSystemComponent.h"
#include "Curves/CurveFloat.h"
#include "Engine/Blueprint.h"
#include "Engine/BlueprintGeneratedClass.h"
#include "Kismet2/KismetEditorUtilities.h"
#include "Dom/JsonObject.h"
#include "Serialization/JsonReader.h"
#include "Serialization/JsonSerializer.h"
#include "Misc/FileHelper.h"
#include "Misc/PackageName.h"
#include "UObject/SavePackage.h"
#include "UObject/Package.h"
#include "UObject/UObjectGlobals.h"
#include "UObject/UnrealType.h"

namespace
{
FString SvLog;
int32 GErrors = 0;

void Say(const FString& S) { SvLog += S + TEXT("\n"); UE_LOG(LogTemp, Display, TEXT("LaserFx: %s"), *S); }
void Bad(const FString& S) { ++GErrors; Say(TEXT("ERROR ") + S); }

UClass* FindClass(const FString& Name)
{
	if (Name.StartsWith(TEXT("/Script/"))) return FindObject<UClass>(nullptr, *Name);
	for (const TCHAR* Mod : { TEXT("/Script/Engine."), TEXT("/Script/Live.") })
	{
		if (UClass* C = FindObject<UClass>(nullptr, *(FString(Mod) + Name))) return C;
	}
	return FindFirstObject<UClass>(*Name, EFindFirstObjectOptions::None);
}

void ApplyProps(UObject* Obj, const TSharedPtr<FJsonObject>& Props);

UObject* BuildDistribution(UObject* Outer, const TSharedPtr<FJsonObject>& Spec)
{
	const FString ClsName = Spec->GetStringField(TEXT("class"));
	UClass* C = FindClass(ClsName);
	if (!C) { Bad(FString::Printf(TEXT("no distribution class %s"), *ClsName)); return nullptr; }
	UObject* D = NewObject<UObject>(Outer, C, NAME_None, RF_Public | RF_Transactional);
	const TSharedPtr<FJsonObject>* P = nullptr;
	if (Spec->TryGetObjectField(TEXT("props"), P)) ApplyProps(D, *P);
	return D;
}

void ApplyProps(UObject* Obj, const TSharedPtr<FJsonObject>& Props)
{
	for (const auto& KV : Props->Values)
	{
		FProperty* Prop = Obj->GetClass()->FindPropertyByName(FName(*KV.Key));
		if (!Prop)
		{
			Say(FString::Printf(TEXT("  (skipped) %s has no property %s"), *Obj->GetClass()->GetName(), *KV.Key));
			continue;
		}
		void* Ptr = Prop->ContainerPtrToValuePtr<void>(Obj);
		if (KV.Value->Type == EJson::Object)
		{
			const TSharedPtr<FJsonObject> V = KV.Value->AsObject();
			const TSharedPtr<FJsonObject>* DSpec = nullptr;
			if (V->TryGetObjectField(TEXT("dist"), DSpec))
			{
				FStructProperty* SP = CastField<FStructProperty>(Prop);
				FObjectPropertyBase* DP = SP ? CastField<FObjectPropertyBase>(SP->Struct->FindPropertyByName(TEXT("Distribution"))) : nullptr;
				if (!DP) { Bad(FString::Printf(TEXT("%s.%s is no raw distribution"), *Obj->GetClass()->GetName(), *KV.Key)); continue; }
				UObject* D = BuildDistribution(Obj, *DSpec);
				if (D) DP->SetObjectPropertyValue(DP->ContainerPtrToValuePtr<void>(Ptr), D);
			}
			continue;
		}
		const FString Text = KV.Value->AsString();
		if (!Prop->ImportText_Direct(*Text, Ptr, Obj, PPF_None))
		{
			Bad(FString::Printf(TEXT("%s.%s: import failed (%s)"), *Obj->GetClass()->GetName(), *KV.Key, *Text.Left(200)));
		}
	}
}

UParticleModule* BuildModule(UParticleSystem* PS, const TSharedPtr<FJsonObject>& Spec)
{
	const FString ClsName = Spec->GetStringField(TEXT("class"));
	UClass* C = FindClass(ClsName);
	if (!C || !C->IsChildOf(UParticleModule::StaticClass())) { Bad(FString::Printf(TEXT("no module class %s"), *ClsName)); return nullptr; }
	UParticleModule* M = NewObject<UParticleModule>(PS, C, NAME_None, RF_Public | RF_Transactional);
	const TSharedPtr<FJsonObject>* P = nullptr;
	if (Spec->TryGetObjectField(TEXT("props"), P)) ApplyProps(M, *P);
	return M;
}

bool Save(UPackage* Pkg, UObject* Asset)
{
	Pkg->MarkPackageDirty();
	const FString File = FPackageName::LongPackageNameToFilename(Pkg->GetName(), FPackageName::GetAssetPackageExtension());
	FSavePackageArgs Args;
	Args.TopLevelFlags = RF_Public | RF_Standalone;
	Args.SaveFlags = SAVE_NoError;
	const bool Ok = UPackage::SavePackage(Pkg, Asset, *File, Args);
	Say(FString::Printf(TEXT("saved %s -> %s: %s"), *Asset->GetPathName(), *File, Ok ? TEXT("ok") : TEXT("FAILED")));
	if (!Ok) ++GErrors;
	return Ok;
}

UParticleSystem* BuildSystem(const FString& Root, const TSharedPtr<FJsonObject>& Spec)
{
	const FString Name = Spec->GetStringField(TEXT("asset"));
	UPackage* Pkg = CreatePackage(*(Root / Name));
	Pkg->FullyLoad();
	UParticleSystem* PS = NewObject<UParticleSystem>(Pkg, FName(*Name), RF_Public | RF_Standalone | RF_Transactional);
	const TSharedPtr<FJsonObject>* P = nullptr;
	if (Spec->TryGetObjectField(TEXT("props"), P)) ApplyProps(PS, *P);
	int32 NMod = 0;
	for (const TSharedPtr<FJsonValue>& EV : Spec->GetArrayField(TEXT("emitters")))
	{
		const TSharedPtr<FJsonObject> ES = EV->AsObject();
		UClass* EC = FindClass(ES->GetStringField(TEXT("class")));
		if (!EC || !EC->IsChildOf(UParticleEmitter::StaticClass())) EC = UParticleSpriteEmitter::StaticClass();
		UParticleEmitter* E = NewObject<UParticleEmitter>(PS, EC, NAME_None, RF_Public | RF_Transactional);
		E->EmitterName = FName(*ES->GetStringField(TEXT("name")));
		if (ES->TryGetObjectField(TEXT("props"), P)) ApplyProps(E, *P);
		int32 Level = 0;
		for (const TSharedPtr<FJsonValue>& LV : ES->GetArrayField(TEXT("lods")))
		{
			const TSharedPtr<FJsonObject> LS = LV->AsObject();
			UParticleLODLevel* L = NewObject<UParticleLODLevel>(E, NAME_None, RF_Public | RF_Transactional);
			L->Level = Level++;
			L->bEnabled = true;
			const TSharedPtr<FJsonObject>* MS = nullptr;
			if (LS->TryGetObjectField(TEXT("required"), MS)) L->RequiredModule = Cast<UParticleModuleRequired>(BuildModule(PS, *MS));
			if (LS->TryGetObjectField(TEXT("spawn"), MS)) L->SpawnModule = Cast<UParticleModuleSpawn>(BuildModule(PS, *MS));
			if (LS->TryGetObjectField(TEXT("typedata"), MS)) L->TypeDataModule = Cast<UParticleModuleTypeDataBase>(BuildModule(PS, *MS));
			if (!L->RequiredModule) { Bad(TEXT("an emitter with no required module")); continue; }
			if (!L->SpawnModule) L->SpawnModule = NewObject<UParticleModuleSpawn>(PS, NAME_None, RF_Public | RF_Transactional);
			NMod += 2 + (L->TypeDataModule ? 1 : 0);
			for (const TSharedPtr<FJsonValue>& MV : LS->GetArrayField(TEXT("modules")))
			{
				if (UParticleModule* M = BuildModule(PS, MV->AsObject())) { L->Modules.Add(M); ++NMod; }
			}
			E->LODLevels.Add(L);
		}
		PS->Emitters.Add(E);
		E->UpdateModuleLists();
	}
	PS->UpdateAllModuleLists();
	PS->PostEditChange();
	Say(FString::Printf(TEXT("%s: %d emitters, %d modules"), *Name, PS->Emitters.Num(), NMod));
	Save(Pkg, PS);
	return PS;
}

UCurveFloat* BuildCurve(const FString& Root, const TSharedPtr<FJsonObject>& Spec)
{
	const FString Name = Spec->GetStringField(TEXT("asset"));
	UPackage* Pkg = CreatePackage(*(Root / Name));
	UCurveFloat* C = NewObject<UCurveFloat>(Pkg, FName(*Name), RF_Public | RF_Standalone | RF_Transactional);
	for (const TSharedPtr<FJsonValue>& KV : Spec->GetArrayField(TEXT("keys")))
	{
		const TSharedPtr<FJsonObject> K = KV->AsObject();
		const FKeyHandle H = C->FloatCurve.AddKey((float)K->GetNumberField(TEXT("t")), (float)K->GetNumberField(TEXT("v")));
		const FString Mode = K->GetStringField(TEXT("interp"));
		C->FloatCurve.SetKeyInterpMode(H, Mode == TEXT("linear") ? RCIM_Linear : Mode == TEXT("constant") ? RCIM_Constant : RCIM_Cubic);
		C->FloatCurve.SetKeyTangentMode(H, RCTM_Auto);
	}
	Say(FString::Printf(TEXT("%s: %d keys, 0.5 -> %.4f"), *Name, C->FloatCurve.GetNumKeys(), C->GetFloatValue(0.5f)));
	Save(Pkg, C);
	return C;
}

UBlueprint* BuildBlueprint(const FString& Root, const TSharedPtr<FJsonObject>& Spec)
{
	const FString Name = Spec->GetStringField(TEXT("asset"));
	UClass* Parent = FindClass(Spec->GetStringField(TEXT("parent")));
	if (!Parent) { Bad(TEXT("no parent class ") + Spec->GetStringField(TEXT("parent"))); return nullptr; }
	UPackage* Pkg = CreatePackage(*(Root / Name));
	UBlueprint* BP = FKismetEditorUtilities::CreateBlueprint(Parent, Pkg, FName(*Name), BPTYPE_Normal,
		UBlueprint::StaticClass(), UBlueprintGeneratedClass::StaticClass(), FName(TEXT("LaserFx")));
	if (!BP || !BP->GeneratedClass) { Bad(TEXT("blueprint not made")); return nullptr; }
	FKismetEditorUtilities::CompileBlueprint(BP);
	UObject* CDO = BP->GeneratedClass->GetDefaultObject();
	const TSharedPtr<FJsonObject>* P = nullptr;
	if (Spec->TryGetObjectField(TEXT("cdo"), P)) ApplyProps(CDO, *P);
	if (Spec->TryGetObjectField(TEXT("components"), P))
	{
		for (const auto& KV : (*P)->Values)
		{
			FObjectPropertyBase* OP = CastField<FObjectPropertyBase>(CDO->GetClass()->FindPropertyByName(FName(*KV.Key)));
			UObject* Comp = OP ? OP->GetObjectPropertyValue(OP->ContainerPtrToValuePtr<void>(CDO)) : nullptr;
			if (!Comp) { Bad(TEXT("no component ") + KV.Key); continue; }
			Comp->Modify();
			ApplyProps(Comp, KV.Value->AsObject());
			Say(FString::Printf(TEXT("component %s (%s) set"), *KV.Key, *Comp->GetClass()->GetName()));
		}
	}
	CDO->Modify();
	FKismetEditorUtilities::CompileBlueprint(BP);
	Say(FString::Printf(TEXT("%s: parent %s, class %s"), *Name, *Parent->GetPathName(), *BP->GeneratedClass->GetPathName()));
	Save(Pkg, BP);
	return BP;
}
}

ULaserFxCommandlet::ULaserFxCommandlet()
{
	IsClient = false;
	IsEditor = true;
	IsServer = false;
	LogToConsole = true;
}

int32 ULaserFxCommandlet::Main(const FString& Params)
{
	FString SpecPath, OutLogPath;
	FParse::Value(*Params, TEXT("spec="), SpecPath);
	FParse::Value(*Params, TEXT("log="), OutLogPath);
	FString Text;
	if (!FFileHelper::LoadFileToString(Text, *SpecPath)) { UE_LOG(LogTemp, Error, TEXT("LaserFx: no spec %s"), *SpecPath); return 1; }
	TSharedPtr<FJsonObject> Root;
	if (!FJsonSerializer::Deserialize(TJsonReaderFactory<>::Create(Text), Root) || !Root.IsValid())
	{
		UE_LOG(LogTemp, Error, TEXT("LaserFx: the spec isn't JSON")); return 1;
	}
	const FString Dir = Root->GetStringField(TEXT("root"));
	const TSharedPtr<FJsonObject>* O = nullptr;
	if (Root->TryGetObjectField(TEXT("curve"), O)) BuildCurve(Dir, *O);
	for (const TSharedPtr<FJsonValue>& S : Root->GetArrayField(TEXT("systems"))) BuildSystem(Dir, S->AsObject());
	if (Root->TryGetObjectField(TEXT("blueprint"), O)) BuildBlueprint(Dir, *O);
	Say(FString::Printf(TEXT("%s (%d errors)"), GErrors == 0 ? TEXT("done") : TEXT("done with errors"), GErrors));
	if (!OutLogPath.IsEmpty()) FFileHelper::SaveStringToFile(SvLog, *OutLogPath);
	return GErrors == 0 ? 0 : 2;
}
