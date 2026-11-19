# Native runtime (runtime/*.c)

Rules for the C runtime (main.dll): hooks, the Lua bridge, logging, the player-input detour.

Moved verbatim from AGENTS.md (2026-11-14). Rule numbers are unchanged: other notes cite them as "hard rule N".

14. A C++ mod adds Lua functions in `CppUserModBase::on_lua_start(mod_name, lua, ...)` (vtable slot 6 in UE4SS 3.0.1,
    called for every Lua mod before its main.lua runs; check the name). Confirmed by test 11 of 2026-10-21.

19. The player's ammo counts are native (the reflected FCS module AmmoCount is only the weapon definition): read and
    set them with SV_Ammo / SV_SetAmmo (runtime 0.7.0, copied from LiveSetWeaponAmmoCount, docs/re/AMMO.md), and turn
    free restock off with SV_FreeRestock(0). The airfield rearm reloads the stock full count, so caps must be
    re-enforced after it, not set once. Confirmed by test 16 (2026-10-22).

25. The native runtime's Lua function names must be 15 characters or fewer: they're registered through a small-string
    buffer and a longer one is skipped (log "function N's name is longer than 15 characters; not registered").
    SV_SetControlInvert never registered (test of 2026-10-22), now SV_Invert. lua_check.py fails the build on one.

28. The player-input detour (runtime BuildFlightInput hook, SV_Invert) inverts pitch / roll in game. The event focus
    camera zooms by distance: the farther its target, the tighter the shot (MINDRIPPER at ~20 km very close, 8-12 km
    wide with ms23-01). Confirmed by the tests of 2026-10-22.

43. The native runtime's Log / VFmt understands only %s %d %u %x %p (%u from runtime 0.18.1). An unknown specifier takes
    no argument, so the next %s reads a number as a string pointer and the game crashes: 0.18.0's sound log used %u
    and crashed AC8 on VALKA's first sound (test of 2026-10-24); after the fix the same path ran clean.

55. The runtime's formatter (runtime/vfmt.h, Log's and Crumb's) must keep reading its input when the line is full: until
    0.32.23 its PUT skipped `*s++` / `t[--n]` past the buffer, so a line over 1,023 characters looped for ever holding the
    log lock. 0.32.22's three new Lua functions made RegisterLua's "Lua bridge: ... registered" line 1,031 characters: UE4SS's
    Lua start never returned, Survival's Lua never ran (no SURVIVAL MODE on the menu) and every later Log waited (the user's
    launches of 2026-11-03 23:33 and 23:48; a crumb before each registration found it). Fixed in 0.32.23, confirmed at 23:54
    (tools/checks/vfmt_test.sh fails on the old macro). A bounded writer must still consume what it's given.
