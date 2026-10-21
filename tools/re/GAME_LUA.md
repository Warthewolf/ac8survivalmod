# The game's own Lua (AI behaviour scripts), reverse-engineered 2026-10-22

Why: the behaviour probe (barrel-roll MiGs, tests 16-21) never showed our script running, and nothing in the game
reports why. This is how the game turns a DT_NPC_LuaSet slot into a running behaviour, and Survival's native bridge
into that Lua (dlls/main.dll 0.8.0).

## The Lua
- **Lua 5.3**, statically linked into AceCombat8.exe, which **exports the whole C API by name** (146 exports:
  `lua_pcallk`, `luaL_loadbufferx`, `lua_getglobal`, `lua_tolstring`, `luaL_traceback`, `luaopen_*`, ...). Use
  `GetProcAddress(GetModuleHandle(NULL), "...")`; no signatures needed. `lua_State`: top +0x10, l_G +0x18, ci +0x20.
- The plugin is UnrealLua (`/Script/LuaPluginRuntime`, `UTableUtil`). Its Lua framework is in
  `/Game/LuaSource/DefaultLua/` (main, frame/initrequire, frame/cppobjectbase, luaclass, ...): `Init()` sets a
  metatable on `_G` whose `__index` calls `UTableUtil.require(k)` (C++ globals on demand), then requires the frame.
- One state: the plugin's **SingleGameluaContext**. `GetGameLuaState()` (0x144ed8940, not exported) returns
  `**ContextSlot()` where ContextSlot (0x144ed84e0) returns the static 0x14dd0ae20 (thread-safe static). If the context
  is missing, GetGameLuaState **creates** it (allocates 0x48 bytes, 0x144ed7c10 ctor, 0x144ed83d0 init). Survival
  only reads the slot (signature kSigGameLuaState, `lea rax,[rip+disp]` at ContextSlot+0x20).

## From a LuaSet slot to a behaviour
1. A behaviour owner walks the slots (LiveLuaAssets: RootLua, EvadeLua, ..., PursueTargetLua). For each slot's
   LuaScript it takes **`LuaInitializePath` (LuaScript +0x48)** and looks it up, case-insensitively, in a cache of
   already-built behaviours (`[this+0x78]`, count `[this+0x80]`, 0x30-byte entries, also keyed by a slot byte)
   (0x1473b47eb.., four such functions). The module name is the only key.
2. On a miss it builds one: `0x1473b3c30(obj, &LuaInitializePath)` converts the path to UTF-8 and, if the plugin is
   on (`[0x14dc4c068] != 0`), calls `0x144ee8e50(L, &classpath, &obj)` = **`Ctor(classpath, obj)`** in Lua under pcall
   (error handler 0x144ebbe00). On error it only turns the message into an FString for a log call that is stripped
   from the shipping game: **every error in a behaviour script is silent**.
3. Lua `Ctor` (DefaultLua/main): `local class = require(classpath)`, then the class's own `Ctor` (via rawget) or
   `class:NewOn(obj)`. Behaviour scripts build their tree in `Ctor` (GenerateBehavior / AddTask / EndGenerateBehavior).
4. `require` -> the plugin's loader **0x144eb8ce0(out, module)**: dots become `/`, `.<last segment>` is appended and
   `/Game/LuaSource/` prepended, e.g. `SurvivalMode.AI.LA_X` -> `/Game/LuaSource/SurvivalMode/AI/LA_X.LA_X`, then
   `StaticLoadObject(LuaScript, null, path)` (0x141ab7400) and the object's `Code` (+0x28) is the source.
   A module already in `package.loaded` never reaches the loader.

## Survival's bridge (dlls/main.dll 0.8.0, survival_rt.c "the game's own Lua")
- `SV_GameLuaState([create])` -> the lua_State address, 0 while none. `create = 1` calls GetGameLuaState (the game's
  own way of making it) - main.lua does that only in Survival's level, 3 s after loading, if there is still none.
- `SV_GameLua(code [, name])` -> `"<status>\t<result>"`: luaL_loadbufferx + lua_pcallk with a luaL_traceback
  message handler, stack restored with lua_settop. Status 0 ok, 2 run-time error, 3 syntax, 4 memory, 6 handler,
  -1 no state yet, -5 game code not found. Runs on the game thread from main.lua's tick (never inside a game Lua call).
- main.lua (section "the game's own Lua") on every new state: logs diagnostics (io/os/debug, Inherit, ...), installs
  `SV_Instrument(name, class)` (wraps a class's Ctor: counts builds, keeps errors with tracebacks, re-raises) and
  `SV_Report()`, wraps the stock LA_AIPlane / PursueTarget_0011 / _0400 for comparison, tries the packaged probe
  script through the game's own require (asset route) and puts it in directly if that fails, and puts the run-time
  script into `package.loaded`. In the level it logs `SV_Report()` every 10 s when it changes.
- Run-time scripts therefore need no package at all: a LuaScript object (any outer) whose LuaInitializePath is the
  module name, in the LuaSet slot, plus the module in package.loaded.
