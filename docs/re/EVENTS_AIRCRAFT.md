# SV_Event and off-mission aircraft (research, 2026-10-22)

Two research items: (1) a native `SV_Event(name)` that fires a remote event of Survival's event package from Lua, so
stock nodes (BGM, radio, focus camera, Helios, ...) can be run from Lua; (2) aircraft types that Mission 22's NPC
table doesn't list. Static analysis of AceCombat8.exe (build of 2026-09-29) only: nothing here has been tested in game.
Scratch is under `build/research/events/` (not in git): disassembly dumps, `re_unmatched.py` (stock remote-event
calls with no trigger). Tools: `tools/re/exe.py`, `mksig.py`, `tools/checks/ep_dump.py`, `build/research/ai/dt.py`.

## 1. SV_Event: firing a remote event natively

### What `LiveCallRemoteEventExecution::Execute` (0x1473f86b0) does, verified
```
push rbx; sub rsp,40h; rbx = this
call 0x146d05ab0(this)                 ; the exec's loop counter bookkeeping, not needed
if (this->EventName (+0x58) == 0) return
ev.vtable = 0x14cb68ce0                ; +0x19  lea rax,[rip+..]      -> [rsp+20h]
ev.types  = {data 0, num 1, max 0}     ; [rsp+28h..3Fh] zeroed, num=1
call 0x1416da210(&ev.types, 0)         ; +0x49  TArray<uint8>::ResizeGrow -> GMalloc (0x14e426090) ->Malloc
ev.types.data[0] = 0x4F                ; +0x56  C6 00 4F
ev.name = this->EventName              ; +0x59  mov rax,[rbx+58h]; +0x5d mov [rsp+38h],rax  (event +0x18)
world = this->vtbl[0x188/8](this)      ; +0x65  FF 90 88 01 00 00 (VF_WORLD, as in the runtime)
sys = 0x1470d2460(world)               ; +0x6e  call: UWorld::GetSubsystem<ULiveEventSubsystem>
                                       ;        (world+0x888 subsystem collection; class name L"LiveEventSubsystem")
mode = (ev.vtbl[9] == 0x1416baca0 /*mov al,1; ret*/ || ev.vtbl[9](&ev)) ? 0 : 2    ; +0x7b lea default, +0x82 [rcx+48h]
call 0x147421660(sys, &ev, mode)       ; +0xaa  Dispatch
~ev (inlined): vtable = 0x14c58d810 (base); if types.data: GMalloc->Free(types.data)  (vtable +0x48)
```
The remote event's slot 9 is the default (returns true), so a remote event is always dispatched with **mode 0**.

### The event object (FLiveRemoteEvent, 0x20 bytes)
| off | field | notes |
|---|---|---|
| +0x00 | vtable 0x14cb68ce0 | base class (FLiveEvent) vtable 0x14c58d810 |
| +0x08 | TArray<uint8> types: data +0x08, num +0x10, max +0x14 | = {0x4F}; the trigger type buckets the event |
| +0x18 | FName EventName (index +0x18, number +0x1C) | copied from the node's +0x58 |

Size: the stack frame holds it at rsp+0x20..0x3F, and the clone (below) copies exactly vtable, types and +0x18.
Vtable 0x14cb68ce0, 13 slots:
| slot | fn | does |
|---|---|---|
| 0 | 0x146d5b370 | destructor: vtable := base, GMalloc->Free(types.data), frees self if flag & 1. **Never call it on Survival's event** |
| 1 | 0x1473cb0c0 | `mov al,4Fh; ret`: the event type (the next class's slot 1, 0x1473cb120, returns 0x50) |
| 6 | 0x146d5b410 | HasType(uint8): scans types |
| 9 | 0x1416baca0 | default `mov al,1; ret` -> mode 0 (local only) |
| 12 | 0x14745a8f0 | Match: `[trigger + 0x10] == [event + 0x18]` as one 8-byte compare, i.e. FName index **and** number |

### Dispatch 0x147421660(ULiveEventSubsystem* sys, FLiveEvent* ev, uint8 mode)
- First `0x147472100(sys)` (+0x2d, a gate). False -> returns at once, the event is silently dropped. The gate reads
  `sys->Outer` (+0x20, the UWorld), wants `world+0x158` (AuthorityGameMode) to be the game's mode class, and then a
  state check (mode +0x780/+0x54, vfunc +0xb70, byte +0x578 in {0xA, 0xC}). It only reads, so it's safe to call first
  to get a "dropped" status.
- mode 0: `t = 0x1470d2810([sys+0x68] + 0x290)` (the event processor), then `0x147423bc0(t, ev, &{0,0,0})`:
  - `0x147424c90(ev)` = MakeShared copy: GMalloc 0x30 bytes = {refcount block (vtable 0x14cb3a848, refs +8/+0xC),
    event copy at +0x10}. Copy-constructor 0x1470d2b70 gives the copy **its own** types allocation (ResizeTo +
    memcpy); the FName is copied to +0x28.
  - `0x147e04470(t, {sharedptr, params})` appends it to a TArray at processor +0x50 (0x20-byte entries, no lock).
    The triggers run when the event subsystem ticks (`LiveEventWorldSubsystemTickFunction`), not inside Dispatch.
- modes 1/2: the same, plus a network send (0x14746ddf0); mode 3 serialises through vfunc 0x50. Not used by
  remote events.

**Lifetime:** the game never keeps or frees the caller's object: it copies it, then the caller destroys its own.
So Survival's event can be a stack struct whose `types.data` points at a **static 1-byte buffer {0x4F}** (num 1,
max 1). It never goes through GMalloc, and nothing frees it, as long as Survival never calls slot 0. The queue is
not thread-safe, so SV_Event must run on the game thread. That already holds: main.lua calls every SV_* inside
`ExecuteInGameThread`.

### Name matching (hard rule 17)
The node's FName comes from the record's string through the engine's FName(TCHAR*), which splits a numeric tail
(`RE_Artillery_Pre_0` = RE_Artillery_Pre, number 1). Trigger EventNames are FNames stored in the package, and Match
compares index + number. `survival_events.fname()` already stores trigger names split, and the runtime's `MakeName`
(UE4SS FName ctor = the game's constructor, FNAME_Find) splits the same way, so `SV_Event("RE_SV_X_3")` matches a
trigger built as `fname("RE_SV_X_3")`. A tail with a leading zero (`_01`) is not split on either side.
`FNAME_Find` fails only if the name was never made, and then no trigger can match it, so that's a cheap
"unknown event" check. Remote triggers (type 0x4F) have no args: matching is on EventName only.
`LifeCount` "-" (unlimited) lets Lua fire the same event again and again.

### A remote event with no matching trigger is harmless
`build/research/events/re_unmatched.py` checks every stock EP in `build/stock`: of 9658 `LiveCallRemoteEventExecution`
calls, about 290 name no type-0x4F trigger in their mission (debug events, cut content). Mission 22 itself fires
`RE_Wave1_AreaB_PathSet` from `RE_Wave01_Start` every run, and that trigger exists nowhere (only `RE_Wave2_AreaB_PathSet`
does). The queued event finds no match and is dropped. The dispatch path has no "not found" branch either.

### Signatures
- `ULiveCallRemoteEventExecution::Execute`, unique (mksig, 51 bytes, 12 wildcards), the only one needed:
```c
static const uint8_t kSigCallRemote[51] = {
    0x40, 0x53, 0x48, 0x83, 0xEC, 0x40, 0x48, 0x8B, 0xD9, 0xE8, 0x00, 0x00, 0x00, 0x00, 0x48, 0x83, 0x7B, 0x58, 0x00,
    0x0F, 0x84, 0x00, 0x00, 0x00, 0x00, 0x48, 0x8D, 0x05, 0x00, 0x00, 0x00, 0x00, 0x48, 0x89, 0x7C, 0x24, 0x50, 0x33,
    0xFF, 0x48, 0x89, 0x44, 0x24, 0x20, 0x33, 0xD2, 0x48, 0x89, 0x7C, 0x24, 0x28,
};
static const uint8_t kSigCallRemoteMask[51] = {
    1,1,1,1,1,1,1,1,1,1,0,0,0,0,1,1,1,1,1, 1,1,0,0,0,0,1,1,1,0,0,0,0,1,1,1,1,1,1, 1,1,1,1,1,1,1,1,1,1,1,1,1,
};
```
- Dispatch has **no unique signature**: an identical twin sits at 0x147421990 (it calls 0x147423d30 instead). Take
  it, the subsystem getter (a templated GetSubsystem body, also not unique) and the vtable from the Execute's bytes.
- Gate 0x147472100 (optional, unique, 42 bytes): read it instead from Dispatch +0x2d (`E8 rel32`).

### Implementation plan (survival_rt.c style, offsets read and checked from the code)
```c
/* sigs.h: kSigCallRemote / kSigCallRemoteMask above; FindFunctions: g_fCallRemote = p[n].hit */
typedef void*   (*EventSysFn)(void* world);
typedef void    (*EventDispatchFn)(void* sys, void* ev, uint8_t mode);
typedef uint8_t (*EventGateFn)(void* sys);
static struct { int state; void* vt; uint8_t type; EventSysFn sys; EventDispatchFn dispatch; EventGateFn gate; } EV;
static uint8_t* RipLea(uint8_t* insn) { return insn + 7 + *(int32_t*)(insn + 3); }   /* 48 8D 05 disp32 */

static int ResolveEvents(void)
{
    if (EV.state) return EV.state > 0;
    EV.state = -1;
    uint8_t* ex = g_fCallRemote;
    if (!ex) { Log(L"events: the game's remote-event node was not found"); return 0; }
    if (memcmp(ex + 0x19, "\x48\x8D\x05", 3) || memcmp(ex + 0x27, "\x48\x89\x44\x24\x20", 5) ||   /* ev at rsp+20h */
        memcmp(ex + 0x56, "\xC6\x00", 2) || memcmp(ex + 0x5d, "\x48\x89\x44\x24\x38", 5) ||      /* name: ev+18h  */
        memcmp(ex + 0x65, "\xFF\x90", 2) || *(int32_t*)(ex + 0x67) != VF_WORLD * 8 || ex[0x6e] != 0xE8 ||
        memcmp(ex + 0x7b, "\x48\x8D\x05", 3) || memcmp(ex + 0x82, "\x48\x8B\x51", 3) || ex[0xaa] != 0xE8) {
        Log(L"events: the remote-event node's code is not the expected shape; SV_Event is off"); return 0;
    }
    EV.vt = RipLea(ex + 0x19);  EV.type = ex[0x58];                       /* 0x4F */
    EV.sys = (EventSysFn)Rel32(ex + 0x6e);  EV.dispatch = (EventDispatchFn)Rel32(ex + 0xaa);
    uint8_t* d = (uint8_t*)EV.dispatch;
    EV.gate = d[0x2d] == 0xE8 ? (EventGateFn)Rel32(d + 0x2d) : NULL;
    void** vt = (void**)EV.vt;  int slot = ex[0x85] / 8;                  /* 9 */
    if (!InGame(EV.vt) || !InGame((void*)EV.sys) || !InGame((void*)EV.dispatch) ||
        memcmp(vt[1], (uint8_t[]){0xB0, EV.type, 0xC3}, 3) ||              /* slot 1: mov al,type; ret */
        vt[slot] != RipLea(ex + 0x7b)) {                                   /* default slot 9 -> mode 0 */
        Log(L"events: event layout implausible; SV_Event is off"); return 0;
    }
    Log(L"events: vtable %p, type %x, subsystem fn %p, dispatch %p, gate %p", EV.vt, EV.type, EV.sys, EV.dispatch, EV.gate);
    EV.state = 1;
    return 1;
}

/* Queue a remote event; its triggers run on the event subsystem's next tick. Game thread only. */
static int64_t FireEvent(const wchar_t* name)
{
    if (!ResolveUE4SS() || !ResolveEvents()) return SV_ERR_NO_GAME;
    int r = SpawnerReady(); if (r != 1) return r;                         /* Survival's level only */
    FNameRaw n; if (!MakeName(name, &n)) return SV_ERR_NO_UNIT;           /* no such name: nothing can match */
    void* world = VCall(g_spawner, VF_WORLD);
    void* sys = LiveObject(world) ? EV.sys(world) : NULL;
    if (!LiveObject(sys)) return SV_ERR_NOT_READY;
    if (EV.gate && !EV.gate(sys)) return SV_ERR_REFUSED;                  /* the game drops events right now */
    static uint8_t types[1];  types[0] = EV.type;                         /* static: the game copies, never frees */
    struct { void* vt; uint8_t* data; int32_t num, max; FNameRaw name; } ev = { EV.vt, types, 1, 1, n };
    EV.dispatch(sys, &ev, 0);                                             /* no destructor call: types isn't GMalloc'd */
    return 1;
}
/* L_Event: ArgName(lua, name, 96) -> Ret(lua, FireEvent(name)); register { "SV_Event", L_Event } */
```
Lua: `SV_Event("RE_SV_Bgm_Ms24A")` -> 1 queued, 0 dropped by the game's gate, -1 not in Survival's level, -2 no such
name, -4 bad args, -5 game code not found. The EP side: `survival_events.py` adds type-0x4F triggers (no args, life
unlimited) named `RE_SV_*`, each with its stock exec records (BGM, radio, focus camera; see MUSIC_RADIO_CAMERA.md).

## 2. Aircraft outside Mission 22's NPC table

### How a MissionNpcID becomes an aircraft (exe, verified)
- `ULiveWorldData.NpcMissionDataTable` (+0x110) is a **hard object import**: WD_SurvivalMode_global's property is
  `('obj', -60)` -> `/Game/Datatables/AI/NPC/Mission/DT_NPC_Mission022` (its package import 4). The WD imports no
  aircraft blueprint. It imports only ships' turret classes (`ChildAIObjectDescs`), the e767 child wings, VFX and
  path conditions. Aircraft AI objects have `AIObjectClass` None.
- `DT_NPC_Model.BlueprintClass` is a **soft class** (e.g. `/Game/Blueprints/Vehicle/AI/Plane/OP1021_su57/CP/BP_OP1021_su57_CP`
  + `.BP_OP1021_su57_CP_C`). The mission NPC table package has no package imports at all.
- **The NPC cache is built once, at spawner start.** `0x147e0fa20` (ALiveUnitSpawner vtable +0x390: calls the AActor
  base first, sets CheckpointWriter +0x688, i.e. its BeginPlay) calls `0x147e071c0(npcSys, wd)` for every phase's world
  data and for `GlobalPhase.WorldData` (+0x348). `npcSys` = `ULiveDataTableNPCSpawnSubSystem` (world subsystem,
  getter 0x1473be810). The builder reads `wd+0x110`, takes **every row** of that table (`UDataTable.RowMap` +0x30),
  builds the full NPC record (0x147e08380: DT_NPC row, model, LuaSet, FCS, ...), and loads the model's blueprint with
  **LoadSynchronous** (0x141a8d5f0 -> FSoftObjectPath::TryLoad 0x141aa5360 -> StaticLoadObject 0x141ab7400, follows
  redirectors). Records are 0x640 bytes: `+0 FName row, +8 UClass*, +0x10 NPC data`. They're kept at
  `npcSys+0x60` = TArray of {TArray<record> (+0 data, +8 num), world-data key +0x10}, 0x18 bytes each.
- **Spawning one AI object** (0x147e09fe0, called per AIObjectDesc by 0x147e0ae60): `rec = 0x147e07120(npcSys, wd,
  &desc.MissionNpcID /*+0x14*/)` (scans the cache: no loading, no table read).
  - Found: class = rec+8 -> SpawnActor (0x14465a120). A null class logs "Error: 機種データテーブルのブループリントクラスの
    読み込みに失敗しました" (failed to load the model table's blueprint class) and spawns nothing.
  - Not found: "Warning: RowName(%s) がミッションNPCデータテーブルで見つかりませんでした。旧機能を使用します"
    (row not in the mission NPC table, legacy path). It falls back to `desc.AIObjectClass` (+0x20, None for aircraft),
    so no aircraft spawns.
  - The per-desc spawn filter 0x147e0b190 does the same lookup. When the spawn's option set is non-empty, an
    unknown row gives a null class there and it reads `[0+0x110]`: a **crash risk**. Never set an uncached id.
- So test 11 worked only because m29a/f14d/su33/su34 are rows of DT_NPC_Mission022. **What decides "works" is the
  cache, not the desc list**: any row of the WD's NPC mission table is loaded at mission start, used by a desc or not.

### Routes compared
| route | works? | notes |
|---|---|---|
| A. **Build time: Survival's own `DT_SV_NpcMission`** (copy of DT_NPC_Mission022 + Survival rows), WD import repointed | yes | in the cache from BeginPlay; no shared table touched; stock BPs load by path |
| B. Run-time AddRow into DT_NPC_Mission022 (menu-row pattern) | no | too late: the cache is built at spawner BeginPlay; and it edits a shared stock table (forbidden) |
| C. Run-time AddRow into DT_SV_NpcMission + native re-run of the builder 0x147e071c0(npcSys, wd) | probably | config-driven types without a rebuild. A second cache entry for the same WD is searched by the lookup (it moves on to the next entry when a name isn't found). Leaks the old entry; does a synchronous load of every row again (cheap: already loaded). Untested; later option |

**Recommended: A.** In `tools/build_survival.py`:
1. `build_npc_table()`: copy `/Game/Datatables/AI/NPC/Mission/DT_NPC_Mission022` to `/Game/Mods/SurvivalMode/Data/DT_SV_NpcMission`
   (`rename_package`). Keep all 46 rows (the descs' own ids must stay valid). Append Survival rows
   (`LiveNpcMissionDataTable`), each cloned from a stock mission row (`f16c_common` for generics, the source mission's
   row for aces, to keep TacName / overrides) with `NpcId` changed. Row keys get an `sv_` prefix. Row keys and NpcId
   values are FNames: store them with `survival_events.fname()` (hard rule 17: `OP1021_su57_Shadow_24` =
   OP1021_su57_Shadow, number 25; `sv_su57_s24` has no split). Add each FName to the name batch (`z.nb.add`).
2. `build_wd_global()`: `retarget_import(z, '/Game/Datatables/AI/NPC/Mission/DT_NPC_Mission022', DATA + 'DT_SV_NpcMission')`.
   pack.py takes the container header's imports from the package's import list, as it does for EP -> WD. Phase WDs
   can keep Mission 22's table: Survival's spawns use the global WD's cache.
3. main.lua `CFG.aircraft` / tier pools name the `sv_*` rows. `SV_SetAircraft` should refuse an id that isn't cached
   (below).

No blueprint imports and no container-header entries are needed for aircraft. Soft paths are loaded by
StaticLoadObject through the IoStore package store, not through the asset registry (hard rule 9 is about UE4SS's
LoadAsset). Hard rule 7 still applies to hard references in descs: `AIObjectClass`, `ChildAIObjectDescs` (ships'
turrets, the e767's child wings), VFX classes. So specials copied as whole descs (Ladon, Aegis, ECM) still need
their stock desc's imports.
Cost: every row's blueprint (and what it hard-references) is loaded at mission start, used or not. Add only the
types the pools use.

### Extra aircraft (all in DT_NPC; all blueprints are in pakchunk0, the base game)
| use | DT_NPC row (NpcId) | model | blueprint (soft, `/Game/Blueprints/Vehicle/AI/Plane/...`) |
|---|---|---|---|
| T3 generic | OP1021_su57_01 | OP1021_su57 | `OP1021_su57/CP/BP_OP1021_su57_CP` |
| T3 generic | OP1005_f22a_01 | OP1005_f22a | `OP1005_f22a/CP/BP_OP1005_f22a_CP` |
| T3 generic | OP1004_f15c_01 / OP1028_su35_01 / OP1011_typn_01 / OP1014_rflm_01 | same names | `OP1004_f15c/CP/BP_OP1004_f15c_CP`, `OP1028_su35/CP/BP_OP1028_su35_CP`, `OP1011_typn/CP/BP_OP1011_typn_CP`, `OP1014_rflm/CP/BP_OP1014_rflm_CP` |
| T3 stealth | OP1006_f35c_01 / OP1018_fa36_01 / OP1019_ea36_01 / OP1026_su47_01 | same | `OP1006_f35c/CP/BP_OP1006_f35c_CP`, `OP1018_fa36/CP/BP_OP1018_fa36_CP`, `OP1019_ea36/CP/BP_OP1019_ea36_CP`, `OP1026_su47/CP/BP_OP1026_su47_CP` |
| T1 | OP1008_j39e_01 (already M022 `j39e_common`) | OP1008_j39e | `OP1008_j39e/CP/BP_OP1008_j39e_CP` |
| aces | OP1021_su57_Shadow_24..28 | OP1021_su57_Shadow | `OP1021_su57/CP/BP_OP1021_su57_CP_Shadow` |
| aces | OP1005_f22a_Shadow_96..99 | OP1005_f22a_Shadow | `OP1005_f22a/CP/BP_OP1005_f22a_CP_Shadow` |
| aces | OP1027_m29a_Shadow_162..168 | OP1020_m29a_Shadow | `OP1020_m29a/CP/BP_OP1020_m29a_CP_Shadow` |
| aces | OP1023_f14d_Shadow_101..109 | OP1023_f14d_Shadow | `OP1023_f14d/CP/BP_OP1023_f14d_CP_Shadow` |
| aces | OP1011_typn_Shadow_32..39 | OP1011_typn_Shadow | `OP1011_typn/CP/BP_OP1011_typn_CP_Shadow` |
| aces | OP1004_f15c_Shark_01..04, OP1028_su35_Ventus_01/02 | ..._Shark, ..._Ventus | `OP1004_f15c/CP/BP_OP1004_f15c_CP_Shark`, `OP1028_su35/CP/BP_OP1028_su35_CP_Ventus` |
| named | e.g. OP1021_su57 `su57_Named` (M029 Sophos), OP1005_f22a_Named (M030), OP1028_su35_Named (M021) | `..._Named` models | `.../CP/BP_<model>_CP_Named` (check each in DT_NPC_Model) |
| specials | OP0045_ladn_01 (16 ChildNPCIds = BP components), OP0008_b01b_01, OP0011_tu95_01, OP1016_x40a_01 | | `OP0045_ladn/CP/BP_OP0045_ladn_CP`, `OP0008_b01b/CP/BP_OP0008_b01b_CP`, `OP0011_tu95/CP/BP_OP0011_tu95_CP`, `OP1016_x40a/CP/BP_OP1016_x40a_CP_Tewy` |
Full model / blueprint list: `python build/research/ai/dt.py build/stock/Datatables/AI/NPC/Model/DT_NPC_Model.uasset LiveModelDataTable`.
Source mission rows for aces: `build/research/ai/mission_npc.tsv` (copy the source row, so TacName and the
override flags come along).

### SV_SetAircraft guard (runtime)
Spawn filter 0x147e0b190 is unique (mksig, 21 bytes, no wildcards:
`48 89 5C 24 08 48 89 74 24 10 57 48 83 EC 20 8B 42 08 49 8B F1`). Read from it: +0x27 `E8` -> GetNpcSpawnSubsystem(world)
(0x1473be810), +0x2c `4C 8D 47 14` -> MissionNpcID offset (0x14, matches LY.aiNpc), +0x36 `E8` -> FindNpcRecord
(0x147e07120; also unique on its own, 24 bytes, no wildcards:
`48 89 5C 24 08 48 89 6C 24 10 48 89 74 24 18 57 48 83 EC 20 48 8B 59 60`). In SetAircraft, before writing:
`rec = FindNpcRecord(GetNpcSys(world), g_wd, &npc); if (!rec || !*(void**)(rec + 8)) return SV_ERR_NO_UNIT;`
Log the row as "not in Survival's NPC table". This turns a silent empty spawn (or the filter crash) into -2.

## Open questions
1. SV_Event: the gate's exact meaning (game mode class 0x1470bb800, state byte +0x578 = 0xA/0xC). Check that it's
   true in Survival's mission during rounds and in the hangar/shop. The return value 0 logs it.
2. SV_Event: the triggers run on the next tick of the event subsystem. Is that the same frame or the next one? It
   matters only if Lua reads a flag right after firing.
3. Slot 12 compares `trigger+0x10`. It's taken to be the runtime trigger's EventName (it fits every stock call), but
   the runtime trigger object wasn't traced.
4. Aircraft: do Shadow / Named rows' special weapons (QAAM, 4AAM, LAAM projectile classes via DT_NPC_FCS/Weapon) load
   through the same record build, or do they need something preloaded? Test one Shadow row (OP1021_su57_Shadow_24) first.
5. Aircraft: test one off-mission generic (sv_su57 = OP1021_su57_01) through route A, and check the log for the two
   messages above. Also measure the extra load time at mission start.
6. Route C (re-running the builder after AddRow): does 0x147e071c0 remove or replace an existing entry for the same WD?
   Read it before trying.
7. Specials as whole descs: Ladon's 16 child NPCs are components (ChildNPCComponentNames), so a Ladon may spawn from a
   fighter desc with only its row. Mission 16's Ladon desc may still carry ChildAIObjectDescs with hard class imports.
   Check before choosing.
