"""tells_lines_check.py : the tells' radio catalog, without the game (tools/checks/tells_test.sh runs it): every
survival_events.TELL_LINES group is letters only, stored whole as an FName, its TextID a voice line's form, its event a
name the Lua runtime (Scripts/sv_config.lua CFG.tells) uses, and every RE_SV_Radio* the runtime names is one of them.
build_survival.py / survival_events.build_tells check the same at build time, and each TextID against the voice bank.
"""
import os
import re
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, os.path.join(HERE, '..'))
import survival_events as se  # noqa: E402

bad = []
groups = [g for g, _, _, _ in se.TELL_LINES]
if len(set(groups)) != len(groups): bad.append('a group twice')
for g, tid, spk, opts in se.TELL_LINES:
    suffix = g[len('SV_Radio_'):]
    if not (g.startswith('SV_Radio_') and suffix.isalpha() and suffix.isascii()): bad.append(f'{g}: not SV_Radio_<letters>')
    if not se.survival_fname_plain(g): bad.append(f'{g}: splits as an FName')
    if not re.match(r'^v\d{4}_\d{4}$', tid): bad.append(f'{g}: TextID {tid}')
    if not re.match(r'^[A-Za-z0-9_]+$', spk): bad.append(f'{g}: speaker {spk}')
    if set(opts) - {'now'}: bad.append(f'{g}: options {opts}')
built = {se.tell_event(g) for g in groups}
used = set(re.findall(r'RE_SV_Radio\w+', se.runtime_lua()))
if used - built: bad.append(f'the runtime names lines the build has none for: {sorted(used - built)}')
if built - used: bad.append(f'lines no tell names: {sorted(built - used)}')
clock = [t for g, t, _, _ in se.TELL_LINES if g.startswith('SV_Radio_Clock')]
if clock != [f'v0001_{307 + k:04d}' for k in range(12)]: bad.append(f'the o\'clock lines: {clock}')
if bad:
    print('tells lines: FAILED\n  ' + '\n  '.join(bad))
    sys.exit(1)
print(f'tells lines: all passed ({len(groups)} lines, {len(built)} events, each named in the Lua catalog)')
