"""lua_check_addons_test.py : tools/checks/lua_check.py --addons (build_all.sh checks examples/addons with it): an
add-on folder is checked against an add-on's environment (docs/ADDONS.md), not Survival's Lua state.
  python -X utf8 -I tools/checks/lua_check_addons_test.py"""
import os
import subprocess
import sys
import tempfile

HERE = os.path.dirname(os.path.abspath(__file__))
fails = 0


def check(ok, what):
    global fails
    print(("  ok   " if ok else "  FAIL ") + what)
    if not ok: fails += 1


def lua_check(root):
    r = subprocess.run([sys.executable, '-X', 'utf8', '-I', os.path.join(HERE, 'lua_check.py'), '--addons', root],
                       capture_output=True, text=True, encoding='utf-8')
    return r.returncode, r.stdout + r.stderr


def addon(root, name, files):
    d = os.path.join(root, name)
    os.makedirs(d)
    for n, src in files.items():
        with open(os.path.join(d, n), 'w', encoding='utf-8', newline='\n') as f: f.write(src)


with tempfile.TemporaryDirectory() as t:
    empty = os.path.join(t, 'empty'); os.makedirs(empty)
    rc, out = lua_check(empty)
    check(rc == 0 and 'no add-on folders' in out, 'no add-on folders: said, no error (an empty folder passes the build)')
    good = os.path.join(t, 'good')
    addon(good, 'a_ok', {'a.lua': 'MINE = 1\nSVP.every(function() if MYADDON_Ready and MINE then SVP.log(string.format("%d", MINE)) end end)\n',
                         'b.lua': 'local x = MINE + 1\nprint(x)\n', 'natives.txt': 'MYADDON_*\n'})
    rc, out = lua_check(good)
    check(rc == 0 and 'ERROR' not in out and 'WARNING' not in out,
          "an add-on using only its environment, its own globals (another file's) and a native its natives.txt names: clean")
    for name, src in (('LoopAsync', 'LoopAsync(100, function() return true end)\n'), ('RegisterHook', 'RegisterHook("/Script/X", print)\n'),
                      ('debug', 'print(debug.traceback())\n'), ('CFG', 'print(CFG.specials)\n'), ('coroutine', 'local c = coroutine.create(print)\n')):
        bad = os.path.join(t, 'bad_' + name)
        addon(bad, 'a_bad', {'a.lua': src})
        rc, out = lua_check(bad)
        check(rc == 1 and ('ERROR line 1: ' + name) in out, f"an add-on that uses {name} (not in its environment): an ERROR, the check fails")
    odd = os.path.join(t, 'odd')
    addon(odd, 'a_odd', {'a.lua': 'print(MYTYPO_VALUE)\n'})
    rc, out = lua_check(odd)
    check(rc == 0 and 'WARNING: unknown global MYTYPO_VALUE' in out, 'a name no one sets that is no one\'s: a warning (a typo, or a native not listed)')
    syn = os.path.join(t, 'syn')
    addon(syn, 'a_syn', {'a.lua': 'if then\n'})
    rc, out = lua_check(syn)
    check(rc == 1 and 'SYNTAX ERROR' in out, 'a syntax error: the check fails')
print('lua_check_addons_test: all passed' if fails == 0 else f'lua_check_addons_test: {fails} FAILED')
sys.exit(1 if fails else 0)
