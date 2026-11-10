// TaniBuildCommandlet: builds the Tanicorn's parts (tools/tanicorn, docs/re/TANICORN.md) from a JSON spec.
//   UnrealEditor-Cmd.exe E:/AC8LiveProject/Live.uproject -run=TaniBuild -spec=<tani.spec.json> -log=<out.log>
// The spec: {
//   "sockets":    [ { "skeleton": "/Game/...", "name", "bone", "loc": [x, y, z], "rot": [pitch, yaw, roll] } ],
//   "mesh_sockets": [ { "mesh": "/Game/...", "name", "loc": [x, y, z], "rot": [pitch, yaw, roll] } ]   on a static mesh
//   "stubs":      [ { "path": "/Game/<stock path>/BP_x", "parent": "<native class>" } ]   stand-ins at stock paths (never
//                  packed: the cooked blueprint imports them by path and the game loads its own)
//   "blueprints": [ { "path": "/Game/.../BP_x", "parent": "<native class>",
//                     "scs": [ { "name", "class", "parent": "<native component or scs name>", "socket", "props": {} } ],
//                     "cdo": { prop: value }, "components": { "<CDO object property>": { prop: value } } } ] }
// A value is text (ImportText), or { "$new": "<class>", "props": {...} } for an instanced object (made in the owner),
// or an array of those. Nothing built here ships but /Game/Mods/SurvivalMode/Tanicorn.
#pragma once
#include "CoreMinimal.h"
#include "Commandlets/Commandlet.h"
#include "TaniBuildCommandlet.generated.h"

UCLASS()
class UTaniBuildCommandlet : public UCommandlet
{
	GENERATED_BODY()
public:
	UTaniBuildCommandlet();
	virtual int32 Main(const FString& Params) override;
};
