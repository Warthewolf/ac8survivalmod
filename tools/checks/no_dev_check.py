"""no_dev_check.py <AC8SurvivalMode folder> : fails (exit 1) when a staged mod for friends holds any of the dev install's
research: the flight recorder (runtime/recorder.c, built only with SV_DEV: SV_FlightRec, its log lines) in
dlls/main.dll, the recorder or the test range in Scripts/*.lua (TEST ONLY blocks: strip_test_only.py takes them out),
or a recordings folder. tools/package_release.sh and package_test.sh run it before they zip (user, 2026-10-31: "none of
this research is allowed to cross over to friends games at all"); package_dev.sh, the user's own install, doesn't."""
import glob
import os
import sys

mod = sys.argv[1]
bad = []
dll = os.path.join(mod, 'dlls', 'main.dll')
if os.path.isfile(dll):
    b = open(dll, 'rb').read()
    for w in ('SV_FlightRec', 'flight recorder'):
        if w.encode() in b or w.encode('utf-16-le') in b:
            bad.append(f'{dll} holds {w!r} (a dev main.dll: build it without DEV=1)')
for f in glob.glob(os.path.join(mod, 'Scripts', '*.lua')):
    s = open(f, encoding='utf-8', errors='replace').read()
    for w in ('SV_FlightRec', 'testRange', 'flight recorder'):
        if w in s:
            bad.append(f'{f} holds {w!r} (a TEST ONLY block left in)')
if os.path.exists(os.path.join(mod, 'recordings')):
    bad.append(os.path.join(mod, 'recordings') + ' is there (flight recordings)')
for m in bad:
    print('DEV CHECK FAILED:', m)
print('dev check: nothing of the dev install in ' + mod if not bad else f'dev check: {len(bad)} FAILED')
sys.exit(1 if bad else 0)
