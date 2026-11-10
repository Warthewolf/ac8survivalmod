// TaniBuildCommandlet.cpp: see TaniBuildCommandlet.h, tools/tanicorn/README.md and docs/re/TANICORN.md.
#include "TaniBuildCommandlet.h"
#include "Engine/Blueprint.h"
#include "Engine/BlueprintGeneratedClass.h"
#include "Engine/SimpleConstructionScript.h"
#include "Engine/SCS_Node.h"
#include "Engine/SkeletalMesh.h"
#include "Engine/SkeletalMeshSocket.h"
#include "Engine/StaticMesh.h"
#include "Engine/StaticMeshSocket.h"
#include "Animation/Skeleton.h"
#include "Components/SceneComponent.h"
#include "GameFramework/Actor.h"
#include "Kismet2/KismetEditorUtilities.h"
#include "Kismet2/BlueprintEditorUtils.h"
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
FString TLog;
int32 TErrors = 0;

void Say(const FString& S) { TLog += S + TEXT("\n"); UE_LOG(LogTemp, Display, TEXT("TaniBuild: %s"), *S); }
void Bad(const FString& S) { ++TErrors; Say(TEXT("ERROR ") + S); }

UClass* FindCls(const FString& Name)
{
	if (Name.StartsWith(TEXT("/"))) return LoadObject<UClass>(nullptr, *Name);
	for (const TCHAR* Mod : { TEXT("/Script/Engine."), TEXT("/Script/Live."), TEXT("/Script/OrcaPlug."), TEXT("/Script/NavigationSystem.") })
	{
		if (UClass* C = FindObject<UClass>(nullptr, *(FString(Mod) + Name))) return C;
	}
	return FindFirstObject<UClass>(*Name, EFindFirstObjectOptions::None);
}

bool SavePkg(UPackage* Pkg, UObject* Asset)
{
	Pkg->MarkPackageDirty();
	const FString File = FPackageName::LongPackageNameToFilename(Pkg->GetName(), FPackageName::GetAssetPackageExtension());
	FSavePackageArgs Args;
	Args.TopLevelFlags = RF_Public | RF_Standalone;
	Args.SaveFlags = SAVE_NoError;
	const bool Ok = UPackage::SavePackage(Pkg, Asset, *File, Args);
	Say(FString::Printf(TEXT("saved %s: %s"), *Asset->GetPathName(), Ok ? TEXT("ok") : TEXT("FAILED")));
	if (!Ok) ++TErrors;
	return Ok;
}

void ApplyProps(UObject* Obj, const TSharedPtr<FJsonObject>& Props);

// An instanced object for an object property: { "$new": class, "props": {...} }, made in Owner with its archetype flags.
UObject* NewInstanced(UObject* Owner, const TSharedPtr<FJsonObject>& Spec)
{
	UClass* C = FindCls(Spec->GetStringField(TEXT("$new")));
	if (!C) { Bad(TEXT("no class ") + Spec->GetStringField(TEXT("$new"))); return nullptr; }
	const EObjectFlags Flags = Owner->GetMaskedFlags(RF_PropagateToSubObjects) | RF_Public;
	UObject* O = NewObject<UObject>(Owner, C, NAME_None, Flags);
	const TSharedPtr<FJsonObject>* P = nullptr;
	if (Spec->TryGetObjectField(TEXT("props"), P)) ApplyProps(O, *P);
	Say(FString::Printf(TEXT("  new %s in %s"), *O->GetName(), *Owner->GetName()));
	return O;
}

bool SetValue(UObject* Owner, FProperty* Prop, void* Ptr, const TSharedPtr<FJsonValue>& V)
{
	if (V->Type == EJson::Object)
	{
		FObjectPropertyBase* OP = CastField<FObjectPropertyBase>(Prop);
		if (!OP) { Bad(FString::Printf(TEXT("%s: an object value for a non-object property"), *Prop->GetName())); return false; }
		UObject* O = NewInstanced(Owner, V->AsObject());
		OP->SetObjectPropertyValue(Ptr, O);
		return O != nullptr;
	}
	if (V->Type == EJson::Array)
	{
		FArrayProperty* AP = CastField<FArrayProperty>(Prop);
		if (!AP) { Bad(FString::Printf(TEXT("%s: an array value for a non-array property"), *Prop->GetName())); return false; }
		FScriptArrayHelper H(AP, Ptr);
		const TArray<TSharedPtr<FJsonValue>>& Items = V->AsArray();
		H.EmptyValues();
		H.AddValues(Items.Num());
		bool Ok = true;
		for (int32 i = 0; i < Items.Num(); ++i) Ok &= SetValue(Owner, AP->Inner, H.GetRawPtr(i), Items[i]);
		return Ok;
	}
	const FString Text = V->AsString();
	if (!Prop->ImportText_Direct(*Text, Ptr, Owner, PPF_None))
	{
		Bad(FString::Printf(TEXT("%s.%s: import failed (%s)"), *Owner->GetClass()->GetName(), *Prop->GetName(), *Text.Left(300)));
		return false;
	}
	return true;
}

void ApplyProps(UObject* Obj, const TSharedPtr<FJsonObject>& Props)
{
	for (const auto& KV : Props->Values)
	{
		FProperty* Prop = Obj->GetClass()->FindPropertyByName(FName(*KV.Key));
		if (!Prop) { Bad(FString::Printf(TEXT("%s has no property %s"), *Obj->GetClass()->GetName(), *KV.Key)); continue; }
		Obj->Modify();
		SetValue(Obj, Prop, Prop->ContainerPtrToValuePtr<void>(Obj), KV.Value);
	}
}

void Sockets(const TArray<TSharedPtr<FJsonValue>>& List)
{
	TSet<USkeleton*> Touched;
	TSet<USkeletalMesh*> TouchedMeshes;
	for (const TSharedPtr<FJsonValue>& V : List)
	{
		const TSharedPtr<FJsonObject> S = V->AsObject();
		USkeleton* Sk = LoadObject<USkeleton>(nullptr, *S->GetStringField(TEXT("skeleton")));
		if (!Sk) { Bad(TEXT("no skeleton ") + S->GetStringField(TEXT("skeleton"))); continue; }
		const FName Name(*S->GetStringField(TEXT("name")));
		const FName Bone(*S->GetStringField(TEXT("bone")));
		const TArray<TSharedPtr<FJsonValue>>& L = S->GetArrayField(TEXT("loc"));
		const FVector Loc(L[0]->AsNumber(), L[1]->AsNumber(), L[2]->AsNumber());
		FRotator Rot(0.0, 0.0, 0.0);
		const TArray<TSharedPtr<FJsonValue>>* R = nullptr;
		if (S->TryGetArrayField(TEXT("rot"), R)) Rot = FRotator((*R)[0]->AsNumber(), (*R)[1]->AsNumber(), (*R)[2]->AsNumber());
		auto Make = [&](UObject* Outer)
		{
			USkeletalMeshSocket* K = NewObject<USkeletalMeshSocket>(Outer, NAME_None, RF_Public | RF_Transactional);
			K->SocketName = Name;
			K->BoneName = Bone;
			K->RelativeLocation = Loc;
			K->RelativeRotation = Rot;
			K->RelativeScale = FVector(1.0, 1.0, 1.0);
			return K;
		};
		Sk->Sockets.RemoveAll([&](const TObjectPtr<USkeletalMeshSocket>& K) { return K && K->SocketName == Name; });
		Sk->Sockets.Add(Make(Sk));
		Touched.Add(Sk);
		Say(FString::Printf(TEXT("socket %s on %s.%s at %s"), *Name.ToString(), *Sk->GetName(), *Bone.ToString(), *Loc.ToString()));
		// (0.74.54) the same socket on the skeletal mesh itself, which the cooked game's socket map reads first: the T5's
		// muzzles on the skeleton alone were never found (the shells left the mesh's origin, 0.74.50-0.74.53)
		FString MeshPath;
		if (S->TryGetStringField(TEXT("mesh"), MeshPath))
		{
			USkeletalMesh* SM = LoadObject<USkeletalMesh>(nullptr, *MeshPath);
			if (!SM) { Bad(TEXT("no skeletal mesh ") + MeshPath); continue; }
			TArray<TObjectPtr<USkeletalMeshSocket>>& ML = SM->GetMeshOnlySocketList();
			ML.RemoveAll([&](const TObjectPtr<USkeletalMeshSocket>& K) { return K && K->SocketName == Name; });
			ML.Add(Make(SM));
			TouchedMeshes.Add(SM);
			Say(FString::Printf(TEXT("socket %s on the mesh %s too"), *Name.ToString(), *SM->GetName()));
		}
	}
	for (USkeleton* Sk : Touched) { Sk->Modify(); SavePkg(Sk->GetOutermost(), Sk); }
	for (USkeletalMesh* SM : TouchedMeshes)
	{
		SM->RebuildSocketMap();
		SM->Modify();
		Say(FString::Printf(TEXT("%s: %d sockets of its own, %d in all"), *SM->GetName(), SM->GetMeshOnlySocketList().Num(), SM->NumSockets()));
		SavePkg(SM->GetOutermost(), SM);
	}
}

// Sockets on a static mesh (the hull's Mount_<part>): { "mesh", "name", "loc": [x, y, z] cm, "rot": [pitch, yaw, roll] }.
void MeshSockets(const TArray<TSharedPtr<FJsonValue>>& List)
{
	TSet<UStaticMesh*> Touched;
	for (const TSharedPtr<FJsonValue>& V : List)
	{
		const TSharedPtr<FJsonObject> S = V->AsObject();
		UStaticMesh* M = LoadObject<UStaticMesh>(nullptr, *S->GetStringField(TEXT("mesh")));
		if (!M) { Bad(TEXT("no static mesh ") + S->GetStringField(TEXT("mesh"))); continue; }
		const FName Name(*S->GetStringField(TEXT("name")));
		M->Sockets.RemoveAll([&](const TObjectPtr<UStaticMeshSocket>& K) { return K && K->SocketName == Name; });
		UStaticMeshSocket* K = NewObject<UStaticMeshSocket>(M, NAME_None, RF_Public | RF_Transactional);
		K->SocketName = Name;
		const TArray<TSharedPtr<FJsonValue>>& L = S->GetArrayField(TEXT("loc"));
		K->RelativeLocation = FVector(L[0]->AsNumber(), L[1]->AsNumber(), L[2]->AsNumber());
		const TArray<TSharedPtr<FJsonValue>>* R = nullptr;
		if (S->TryGetArrayField(TEXT("rot"), R)) K->RelativeRotation = FRotator((*R)[0]->AsNumber(), (*R)[1]->AsNumber(), (*R)[2]->AsNumber());
		K->RelativeScale = FVector(1.0, 1.0, 1.0);
		M->Sockets.Add(K);
		Touched.Add(M);
		Say(FString::Printf(TEXT("socket %s on %s at %s rot %s"), *Name.ToString(), *M->GetName(), *K->RelativeLocation.ToString(), *K->RelativeRotation.ToString()));
	}
	for (UStaticMesh* M : Touched)
	{
		M->Modify();
		Say(FString::Printf(TEXT("%s: %d sockets"), *M->GetName(), M->Sockets.Num()));
		SavePkg(M->GetOutermost(), M);
	}
}

UBlueprint* MakeBlueprint(const FString& Path, UClass* Parent)
{
	const FString Name = FPackageName::GetShortName(Path);
	UPackage* Pkg = CreatePackage(*Path);
	Pkg->FullyLoad();
	if (UObject* Old = FindObject<UObject>(Pkg, *Name)) { Bad(TEXT("already exists (delete it first): ") + Path); return nullptr; }
	UBlueprint* BP = FKismetEditorUtilities::CreateBlueprint(Parent, Pkg, FName(*Name), BPTYPE_Normal,
		UBlueprint::StaticClass(), UBlueprintGeneratedClass::StaticClass(), FName(TEXT("TaniBuild")));
	if (!BP || !BP->GeneratedClass) { Bad(TEXT("blueprint not made: ") + Path); return nullptr; }
	return BP;
}

void Stub(const TSharedPtr<FJsonObject>& S)
{
	const FString Path = S->GetStringField(TEXT("path"));
	if (FPackageName::DoesPackageExist(Path)) { Say(TEXT("stub there already: ") + Path); return; }
	UClass* Parent = FindCls(S->GetStringField(TEXT("parent")));
	if (!Parent) { Bad(TEXT("no parent class ") + S->GetStringField(TEXT("parent"))); return; }
	if (UBlueprint* BP = MakeBlueprint(Path, Parent))
	{
		FKismetEditorUtilities::CompileBlueprint(BP);
		Say(FString::Printf(TEXT("stub %s on %s"), *Path, *Parent->GetName()));
		SavePkg(BP->GetOutermost(), BP);
	}
}

void Blueprint(const TSharedPtr<FJsonObject>& Spec)
{
	const FString Path = Spec->GetStringField(TEXT("path"));
	UClass* Parent = FindCls(Spec->GetStringField(TEXT("parent")));
	if (!Parent) { Bad(TEXT("no parent class ") + Spec->GetStringField(TEXT("parent"))); return; }
	UBlueprint* BP = MakeBlueprint(Path, Parent);
	if (!BP) return;
	USimpleConstructionScript* SCS = BP->SimpleConstructionScript;
	AActor* ParentCDO = Cast<AActor>(Parent->GetDefaultObject());
	TMap<FString, USCS_Node*> Nodes;
	const TArray<TSharedPtr<FJsonValue>>* List = nullptr;
	if (Spec->TryGetArrayField(TEXT("scs"), List))
	{
		for (const TSharedPtr<FJsonValue>& V : *List)
		{
			const TSharedPtr<FJsonObject> N = V->AsObject();
			UClass* C = FindCls(N->GetStringField(TEXT("class")));
			if (!C) { Bad(TEXT("no component class ") + N->GetStringField(TEXT("class"))); continue; }
			USCS_Node* Node = SCS->CreateNode(C, FName(*N->GetStringField(TEXT("name"))));
			const FString P = N->GetStringField(TEXT("parent"));
			USceneComponent* Native = nullptr;
			if (ParentCDO)
			{
				for (UActorComponent* AC : ParentCDO->GetComponents())
				{
					if (AC && AC->GetFName() == FName(*P)) { Native = Cast<USceneComponent>(AC); break; }
				}
			}
			if (Native) { Node->SetParent(Native); SCS->AddNode(Node); }
			else if (USCS_Node** Up = Nodes.Find(P)) { (*Up)->AddChildNode(Node); }
			else { SCS->AddNode(Node); if (!P.IsEmpty()) Bad(TEXT("no parent component ") + P); }
			FString Sock;
			if (N->TryGetStringField(TEXT("socket"), Sock)) Node->AttachToName = FName(*Sock);
			const TSharedPtr<FJsonObject>* Props = nullptr;
			if (N->TryGetObjectField(TEXT("props"), Props)) ApplyProps(Node->ComponentTemplate, *Props);
			Nodes.Add(N->GetStringField(TEXT("name")), Node);
			Say(FString::Printf(TEXT("component %s (%s) on %s%s"), *N->GetStringField(TEXT("name")), *C->GetName(), *P,
				Native ? TEXT(" (native)") : TEXT("")));
		}
	}
	FKismetEditorUtilities::CompileBlueprint(BP);
	// the native components' values and the CDO's, after the last compile (a recompile copies the CDO again)
	UObject* CDO = BP->GeneratedClass->GetDefaultObject();
	const TSharedPtr<FJsonObject>* P = nullptr;
	if (Spec->TryGetObjectField(TEXT("cdo"), P)) ApplyProps(CDO, *P);
	if (Spec->TryGetObjectField(TEXT("components"), P))
	{
		for (const auto& KV : (*P)->Values)
		{
			FObjectPropertyBase* OP = CastField<FObjectPropertyBase>(CDO->GetClass()->FindPropertyByName(FName(*KV.Key)));
			UObject* Comp = OP ? OP->GetObjectPropertyValue(OP->ContainerPtrToValuePtr<void>(CDO)) : nullptr;
			if (!Comp) { Bad(TEXT("no native component ") + KV.Key); continue; }
			ApplyProps(Comp, KV.Value->AsObject());
			Say(FString::Printf(TEXT("native %s (%s %s) set"), *KV.Key, *Comp->GetClass()->GetName(), *Comp->GetPathName()));
		}
	}
	CDO->Modify();
	BP->MarkPackageDirty();
	Say(FString::Printf(TEXT("%s: parent %s, class %s"), *Path, *Parent->GetPathName(), *BP->GeneratedClass->GetPathName()));
	SavePkg(BP->GetOutermost(), BP);
}
}

UTaniBuildCommandlet::UTaniBuildCommandlet()
{
	IsClient = false;
	IsEditor = true;
	IsServer = false;
	LogToConsole = true;
}

int32 UTaniBuildCommandlet::Main(const FString& Params)
{
	FString SpecPath, OutLogPath;
	FParse::Value(*Params, TEXT("spec="), SpecPath);
	FParse::Value(*Params, TEXT("log="), OutLogPath);
	FString Text;
	if (!FFileHelper::LoadFileToString(Text, *SpecPath)) { UE_LOG(LogTemp, Error, TEXT("TaniBuild: no spec %s"), *SpecPath); return 1; }
	TSharedPtr<FJsonObject> Root;
	if (!FJsonSerializer::Deserialize(TJsonReaderFactory<>::Create(Text), Root) || !Root.IsValid())
	{
		UE_LOG(LogTemp, Error, TEXT("TaniBuild: the spec isn't JSON")); return 1;
	}
	const TArray<TSharedPtr<FJsonValue>>* L = nullptr;
	if (Root->TryGetArrayField(TEXT("sockets"), L)) Sockets(*L);
	if (Root->TryGetArrayField(TEXT("mesh_sockets"), L)) MeshSockets(*L);
	if (Root->TryGetArrayField(TEXT("stubs"), L)) for (const TSharedPtr<FJsonValue>& V : *L) Stub(V->AsObject());
	if (Root->TryGetArrayField(TEXT("blueprints"), L)) for (const TSharedPtr<FJsonValue>& V : *L) Blueprint(V->AsObject());
	Say(FString::Printf(TEXT("%s (%d errors)"), TErrors == 0 ? TEXT("done") : TEXT("done with errors"), TErrors));
	if (!OutLogPath.IsEmpty()) FFileHelper::SaveStringToFile(TLog, *OutLogPath);
	return TErrors == 0 ? 0 : 2;
}
