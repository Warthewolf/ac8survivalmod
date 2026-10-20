"""execvt.py : vtable and Execute (slot 87) of the game's event-node classes (ULive*Execution, ULive*Statement, ...).

  python execvt.py <Class> [<Class> ...]     e.g. LiveCallRemoteEventExecution (no U prefix)

UE's compiled-in class registry holds {Z_Construct_UClass_X, X::StaticClass, L"UX", &RegistrationInfo, version} per
class (40 bytes). StaticClass calls GetPrivateStaticClassBody with the class constructor (InternalConstructor<X>) on the
stack; that constructor stores X's vtable ("lea rax, [vtable]" ... "mov [rbx], rax"). Checked on
LiveReinforcementExecution: slot 87 = 0x1473e0ee0, the Execute found by tracing (re/SPAWN_SYSTEM.md).
"""
import os, re, struct, sys
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from exe import Exe
from refl import Refl

EXECUTE_SLOT = 87


def lea_targets(text):
    return [(int(a, 16), reg, int(t, 16)) for a, reg, t in
            re.findall(r'^\s*([0-9a-f]+):\s+lea\s+(\w+), \[rip [+-] 0x[0-9a-f]+\]\s+# 0x([0-9a-f]+)', text, re.M)]


def class_info(x, r, cls):
    name = 'U' + cls
    vas = x.wstr_addrs(name)
    for v in vas:
        for ref in r.ptr_refs(v):
            static_class = r.q(ref - 8)
            sc = x.func(static_class)
            if not sc: continue
            t = x.disasm(*sc)
            # the constructor is the function whose address is stored at [r11 - 0x30] / [rsp + 0x48]
            m = re.search(r'lea\s+rax, \[rip [+-] 0x[0-9a-f]+\]\s+# 0x([0-9a-f]+)\n[^\n]*mov\s+qword ptr \[r11 - 0x30\], rax', t)
            if not m: continue
            ctor = int(m.group(1), 16)
            ct = x.disasm(*(x.func(ctor) or (ctor, ctor + 0x80)))   # a leaf constructor has no .pdata entry
            vt = None
            for mm in re.finditer(r'lea\s+(\w+), \[rip [+-] 0x[0-9a-f]+\]\s+# 0x([0-9a-f]+)', ct):
                reg, tgt = mm.group(1), int(mm.group(2), 16)
                if re.search(r'mov\s+qword ptr \[r[a-z0-9]+\], ' + reg + r'\b', ct[mm.end():]):
                    vt = tgt
            return {'static_class': static_class, 'ctor': ctor, 'vtable': vt}
    return None


if __name__ == '__main__':
    x = Exe(); r = Refl(x)
    for cls in sys.argv[1:]:
        ci = class_info(x, r, cls)
        if not ci or not ci['vtable']:
            print(f'{cls}: not found'); continue
        ex = r.q(ci['vtable'] + 8 * EXECUTE_SLOT)
        print(f"{cls}: StaticClass {ci['static_class']:x}  ctor {ci['ctor']:x}  vtable {ci['vtable']:x}  Execute {ex:x}")
