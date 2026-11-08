# Player ammo (reverse-engineered 2026-10-22, for the ammo cap and the airfield shop)

## What doesn't work
- `LiveFCSModule_ProjectileCommon / _ProjectileMulti / _ProjectileFlare` have reflected `bLimitAmmo` / `AmmoCount`,
  but no live instances exist in a mission (test 14, Lua 0.8.0: "no weapon modules found", none in the level at all):
  they are weapon *definitions* (blueprint defaults), not the player's live counts.
- The cheat manager's `SetAmmoMax` / `SetAmmoMin` / `GimmeAmmo` are debug exec commands (likely empty in shipping).

## The stock node: ULiveSetWeaponAmmoCount (Mission 015 uses it at Default_MissionStart)
- Args as stored in the EP: WeaponType (`ELiveSetWeaponAmmoCountWeaponType`: Gun 0, Main 1, Sp1 2, Sp2 3, Flare 4),
  SetType (`ELiveSetWeaponAmmoCountSetType`: Zero 0, Full 1, Direct 2), Value (int). Object fields: +0x58 weapon type,
  +0x59 set type, +0x5c value. Direct with a negative value is skipped.
- Constructor 0x158e0ce60 (reached through a jmp at 0x146dfc2e0; the class's StaticClass is 0x146def230), vtable
  0x14c675da0, Execute (slot 87) 0x147403fb0. execvt.py misses it because the constructor is behind that jmp.
- Execute: `world = this->GetWorld()` (vfunc 0x188); `owner = 0x147edcd00(world)` (walks to the world, then
  `0x14721cb50(world)+0x1e0`); `W = [owner + 0x16a8]`, the player's weapon object. Then one lambda per weapon type:
  - gun / main / sp1 / sp2: 0x147404460 computes all four new counts with the helper 0x1474041c0 (a type that isn't
    the node's gets its current count back) and calls `0x147f62b00(W, gun, main, sp1, sp2)`.
  - flares: 0x14741f3e0: `[[W+0x2e0]+0xc4] = min(new, [W+0x27c])`, then `0x147f77050([W+0x2e0]+0xb8)`.
- Helper 0x1474041c0 (count for one type): weapon slots are `S = [W+0x2e8]`, data `[S+0x28]`, count `[S+0x30]`,
  0xa0 bytes per slot, slot i: max +0x8, current +0xc (a missing slot gives -1). Zero -> 0, Full -> max,
  Direct -> min(value, max). Flares: current `[W+0x2e0]+0xc4`, max `W+0x27c`.

## Survival's version (runtime 0.7.0, survival_rt.c "player ammo")
- Signatures (sigs.h): the node's Execute, its flare lambda and its weapons lambda (each unique in the exe). Every
  offset and function above is read from their bytes at run time (opcode bytes checked first; log line "ammo layout").
- World: `GetWorld` of the level's LiveUnitSpawner (Survival's level only).
- Lua: `SV_Ammo(kind [, max])` -> current or maximum count; `SV_SetAmmo(kind, count)` -> new count, capped at the
  maximum (count < 0 = full). kind: 0 gun, 1 missiles, 2 special 1, 3 special 2, 4 flares. -7 = the aircraft has no
  such slot; -1 not ready; -5 game code not found.
- The maximum stays the aircraft's own full load: caps can only lower the count. The shop's "refill to a cap" is
  `SV_SetAmmo(kind, cap)` too.
- Lua 0.8.1: caps set 2 s after the aircraft appears (CFG.ammo presets by difficulty), the gun refilled every 2 s
  (unlimited), free restock off (below), counts logged every 10 s when they change.

## Free restock (missiles refill over time by default)
- `ULiveSetMissileFreeRestockEnabled` (Execute 0x147405bc0): `[[W+0x2e0]+0x164] = enabled` (W as above; +0x2e0 is
  the same object that holds the flare count). Mission 015 turns it off at Default_MissionStart. The rate comes from
  the player plane's weapon config (`FreeRestockAmount`, `FreeRestockTime`, `FreeRestockTimeMultiplier`, next to
  MachineGunClass / MainWeaponClass / SpecialWeaponConfigs / FlareClass).
- Runtime 0.7.0: `SV_FreeRestock(on)` -> old value; offset read from that Execute's bytes (signature kSigFreeRestock).
  Lua 0.8.1 turns it off with the caps (CFG.ammo.free_restock = false).
