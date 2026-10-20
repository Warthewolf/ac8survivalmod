"""refl.py : read Unreal's compiled-in reflection data (UE5 UECodeGen_Private params) out of AceCombat8.exe.

  python refl.py func <FunctionName>     owning class, flags and parameters of a UFUNCTION (every match)
  python refl.py class <ClassName>       a class's UFUNCTION list (from its FClassParams function link array)

UE5 codegen keeps names as UTF-8 C strings referenced by absolute pointers (relocated), so a name is found by its
bytes, then the structs pointing at it: FFunctionParams {OuterFunc, SuperFunc, NameUTF8, ...PropertyArray...},
FPropertyParamsBase {NameUTF8, RepNotifyFuncUTF8, PropertyFlags, Flags (type), ObjectFlags, ...}, and a class's
FClassFunctionLinkInfo {CreateFuncPtr, FuncNameUTF8}. Layout details are matched loosely so a minor UE version
change still reads.
"""
import os, struct, sys
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from exe import Exe

# EPropertyGenFlags (UE5.1+): low 6 bits = type
GEN = {0x00: 'Byte', 0x01: 'Int8', 0x02: 'Int16', 0x03: 'Int', 0x04: 'Int64', 0x05: 'UInt16', 0x06: 'UInt32',
       0x07: 'UInt64', 0x08: 'UnsizedInt', 0x09: 'UnsizedUInt', 0x0A: 'Float', 0x0B: 'Double', 0x0C: 'Bool',
       0x0D: 'SoftClass', 0x0E: 'WeakObject', 0x0F: 'LazyObject', 0x10: 'SoftObject', 0x11: 'Class', 0x12: 'Object',
       0x13: 'Interface', 0x14: 'Name', 0x15: 'Str', 0x16: 'Array', 0x17: 'Map', 0x18: 'Set', 0x19: 'Struct',
       0x1A: 'Delegate', 0x1B: 'InlineMulticastDelegate', 0x1C: 'SparseMulticastDelegate', 0x1D: 'Text',
       0x1E: 'Enum', 0x1F: 'FieldPath', 0x20: 'LargeWorldCoordinatesReal', 0x21: 'Optional', 0x22: 'VerseValue'}
CPF_Parm, CPF_OutParm, CPF_ReturnParm, CPF_ReferenceParm, CPF_ConstParm = 0x80, 0x100, 0x400, 0x8000000, 0x2


class Refl:
    def __init__(self, x):
        self.x = x
        self.data = [(va, vs, ra, rs) for (n, va, vs, ra, rs, ch) in x.secs if not ch & 0x20000000]   # not code

    def va2off(self, va):
        for (n, sva, vs, ra, rs, ch) in self.x.secs:
            if self.x.base + sva <= va < self.x.base + sva + rs: return va - self.x.base - sva + ra
        return None

    def cstr(self, va, n=128):
        o = self.va2off(va)
        if o is None: return None
        e = self.x.d.find(b'\0', o, o + n)
        if e < 0: return None
        s = self.x.d[o:e]
        return s.decode('latin1') if s and all(32 <= c < 127 for c in s) else None

    def q(self, va):
        o = self.va2off(va)
        return struct.unpack_from('<Q', self.x.d, o)[0] if o is not None else None

    def cstr_vas(self, s):
        d, b, out, i = self.x.d, s.encode() + b'\0', [], 0
        while True:
            i = d.find(b, i)
            if i < 0: return out
            if i == 0 or d[i - 1] == 0:
                for (n, sva, vs, ra, rs, ch) in self.x.secs:
                    if ra <= i < ra + rs: out.append(self.x.base + sva + i - ra)
            i += 1

    def ptr_refs(self, va):
        """File offsets -> VAs of 8-byte absolute pointers equal to va (in data sections)."""
        d, b, out, i = self.x.d, struct.pack('<Q', va), [], 0
        while True:
            i = d.find(b, i)
            if i < 0: return out
            if i % 8 == 0:
                for (n, sva, vs, ra, rs, ch) in self.x.secs:
                    if ra <= i < ra + rs and not ch & 0x20000000: out.append(self.x.base + sva + i - ra)
            i += 1

    def prop(self, pva):
        """FPropertyParamsBase at pva -> (name, type, flags)."""
        name = self.cstr(self.q(pva) or 0)
        flags = self.q(pva + 16)
        gen = self.x.d[self.va2off(pva + 24)] & 0x3F
        return name, GEN.get(gen, hex(gen)), flags

    def enum_or_struct(self, pva, typ):
        """For Enum / Struct / Object params, the name of the referenced type when its constructor is simple."""
        return None

    def func_at(self, name_ref):
        """FFunctionParams around the NameUTF8 pointer at name_ref."""
        base = name_ref - 16                       # OuterFunc, SuperFunc, NameUTF8
        outer = self.q(base)
        props = []
        for k in range(3, 8):                      # PropertyArray is a few qwords after the name
            arr = self.q(base + 8 * k)
            if not arr or self.va2off(arr) is None: continue
            first = self.q(arr)
            if first and self.va2off(first) is not None and self.cstr(self.q(first) or 0):
                n = struct.unpack_from('<H', self.x.d, self.va2off(base + 8 * (k + 1)))[0]
                if 0 < n < 64:
                    props = [self.prop(self.q(arr + 8 * j)) for j in range(n)]
                    return outer, props
        return outer, props

    def classes_with(self, fname):
        """Function link infos {CreateFuncPtr, FuncNameUTF8}: classes listing fname -> their other function names."""
        out = []
        for sva in self.cstr_vas(fname):
            for ref in self.ptr_refs(sva):
                create = self.q(ref - 8)
                if not create or self.va2off(create) is None: continue
                # walk the link array both ways while entries look like {code ptr, name ptr}
                names, a = [], ref - 8
                while True:
                    p = self.cstr(self.q(a - 16 + 8) or 0)
                    if not p or p[0] in '0123456789': break
                    a -= 16
                start = a
                while True:
                    p = self.cstr(self.q(a + 8) or 0)
                    if not p: break
                    names.append(p); a += 16
                if len(names) > 0 and fname in names: out.append((ref, names))
        return out


def main():
    x = Exe(); r = Refl(x)
    what, name = sys.argv[1], sys.argv[2]
    if what == 'func':
        for sva in r.cstr_vas(name):
            for ref in r.ptr_refs(sva):
                outer, props = r.func_at(ref)
                print(f'name ref {ref:x}  outer {outer:x}')
                for (pn, pt, fl) in props:
                    kind = 'return' if fl & CPF_ReturnParm else ('out' if fl & CPF_OutParm and not fl & CPF_ReferenceParm else 'in')
                    print(f'   {kind:6} {pt:14} {pn}   flags {fl:x}')
        for ref, names in r.classes_with(name):
            print(f'link array near {ref:x}: {", ".join(names)}')
    elif what == 'class':
        for ref, names in r.classes_with(name):
            print(f'{ref:x}: {", ".join(names)}')


if __name__ == '__main__':
    main()
