# make_scriptobjs.py : build tools/scriptobjs.pkl (script import index -> name) from retoc's print-script-objects dump
# (build/scan/script_objects.txt). zen_ep.py uses it to name EP node classes.
import pickle, re, os
here = os.path.dirname(os.path.abspath(__file__))
txt = open(os.path.join(here, '..', 'build', 'scan', 'script_objects.txt'), encoding='utf-8', errors='replace').read()
so = {}
for m in re.finditer(r'^(\S[^\n]*):\n  global_index:\s+Some\((\d+)\)', txt, re.M):
    so[int(m.group(2))] = m.group(1)
pickle.dump(so, open(os.path.join(here, 'scriptobjs.pkl'), 'wb'))
print(len(so), 'script objects')
