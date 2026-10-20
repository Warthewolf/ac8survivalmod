# ep_dump.py <EP package> [regex] : list an event package's triggers and execs, readable.
# Record layout after the LiveEventPackage properties: u32 0, u32 trigger count, LiveCustomEventTriggerTable x n,
# u32 exec count, LiveCustomEventExecutionTable x n (unversioned property structs, read with uprop).
#   TRIG EventName  life=LifeCount type=EventType  monitor=[MonitorEvents]  args
#   EXEC ConnectionEventName  class  delay  loop  cond=[ConditionalStatementTables]  args
# A trigger with EventName X fires the execs whose ConnectionEventName is X. With a regex, matching lines only.
import os, re, sys, pickle, struct
HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, os.path.join(HERE, '..')); sys.path.insert(0, os.path.join(HERE, '..', 'scripts'))
from zenpkg import ZenPkg
import uprop

SO = pickle.load(open(os.path.join(HERE, '..', 'scriptobjs.pkl'), 'rb'))


def load(path):
    """-> (zen package, export index, props, triggers, execs, offsets (props end, trig start, exec start, end, size))"""
    return load_bytes(ZenPkg(path))


def load_bytes(z):
    """Same as load(), for a ZenPkg already in memory (e.g. one the build just wrote)."""
    i = max(range(len(z.payloads)), key=lambda k: len(z.payloads[k]))
    p = bytes(z.payloads[i])
    c = uprop.Ctx(p, z.names)
    v, o = uprop.read_struct(c, 4, 'LiveEventPackage')
    assert p[o:o + 4] == b'\0\0\0\0', p[o:o + 8].hex()
    n = struct.unpack_from('<I', p, o + 4)[0]; q = o + 8; t0 = q
    trig = []
    for _ in range(n):
        r, q = uprop.read_struct(c, q, 'LiveCustomEventTriggerTable'); trig.append(r)
    n = struct.unpack_from('<I', p, q)[0]; q += 4; e0 = q
    ex = []
    for _ in range(n):
        r, q = uprop.read_struct(c, q, 'LiveCustomEventExecutionTable'); ex.append(r)
    return z, i, v, trig, ex, (o, t0, e0, q, len(p))


def fields(rec):
    return {p[1]: p[3] for p in rec[2]}


def show(v, z):
    """Compact text for a property value."""
    if v is None: return '-'
    k = v[0]
    if k == 'name': return v[1] + (f'_{v[2] - 1}' if v[2] else '')
    if k == 'str': return v[1]
    if k == 'raw':
        t, b = v[1], v[2]
        if t == 'Float': return f'{struct.unpack("<f", b)[0]:g}'
        if t in ('Int', 'UInt32'): return str(struct.unpack('<i' if t == 'Int' else '<I', b)[0])
        if t == 'Bool': return str(bool(b[0]))
        return b.hex()
    if k == 'enum': return show(v[2], z)
    if k == 'obj':
        i = v[1]
        if i < 0 and -i - 1 < len(z.imports): return SO.get(z.imports[-i - 1], f'imp:{z.imports[-i - 1]:x}')
        return f'obj:{i}'
    if k == 'arr': return '[' + ', '.join(show(x, z) for x in v[1]) + ']'
    if k == 'struct': return '{' + ', '.join(f'{p[1]}={show(p[3], z)}' for p in v[2] if not p[2]) + '}'
    return str(v)[:80]


def args(f, z):
    a = f.get('ArgsInfo')
    if not a: return ''
    out = []
    for item in a[1]:
        d = {p[1]: p[3] for p in item[2]}
        out.append(show(d.get('Value') or d.get('ArgValue') or item, z) if len(d) <= 2 else show(item, z))
    return ' | '.join(out)


if __name__ == '__main__':
    z, i, v, T, E, offs = load(sys.argv[1])
    rx = re.compile(sys.argv[2], re.I) if len(sys.argv) > 2 else None
    print(f'{len(T)} triggers, {len(E)} execs; payload {offs[-1]} bytes, records end at {offs[3]}')
    for t in T:
        f = fields(t)
        line = (f"TRIG {show(f.get('EventName'), z):48} life={show(f.get('LifeCount'), z):3} "
                f"type={show(f.get('EventType'), z):4} mon={show(f.get('MonitorEvents'), z)} {args(f, z)}")
        if not rx or rx.search(line): print(line)
    for e in E:
        f = fields(e)
        line = (f"EXEC {show(f.get('ConnectionEventName'), z):48} {show(f.get('ExecutionClass'), z):44} "
                f"delay={show(f.get('Delay'), z)} loop={show(f.get('LoopCount'), z)} "
                f"cond={show(f.get('ConditionalStatementTables'), z)} {args(f, z)}")
        if not rx or rx.search(line): print(line)
