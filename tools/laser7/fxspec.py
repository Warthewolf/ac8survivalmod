"""fxspec.py : AC7's cooked Cascade particle system (a UAssetGUI JSON dump, UE 4.18) -> a build spec for UE 5.4.

  python -I tools/laser7/fxspec.py <system.json> <out.spec.json> [--map AC7Name=/Game/Path/Asset ...]

AC7's cook baked most distributions into lookup tables (FDistributionLookupTable: Op, EntryCount, EntryStride,
SubEntryStride, TimeScale, TimeBias, Values) and dropped the distribution objects; only the particle parameters
(DistributionFloat/VectorParticleParameter: BeamLength, BeamLifeTime, LightLifeTime) and a few others stay objects. Each
table is turned back into a distribution UE 5.4 can build:
  Op 1 (none), 1 entry       -> Distribution<Float|Vector>Constant
  Op 2 (random), 1 entry     -> Distribution<Float|Vector>Uniform (min / max)
  Op 1, n entries            -> Distribution<Float|Vector>ConstantCurve, a point per entry (t = TimeBias + i / TimeScale)
  Op 2, n entries            -> Distribution<Float|Vector>UniformCurve
The spec (read by the LaserFx commandlet, tools/laser7/cpp) holds every object as { class, props } with props as UE
import-text strings, distributions as nested objects ({"dist": {...}}), references to other assets mapped by --map (AC7's
materials and meshes -> Survival's rebuilt ones). Nothing of AC7's is written here but numbers and names.
"""
import json, sys

FLOAT_TABLE_STRUCTS = {'RawDistributionFloat'}
VECTOR_TABLE_STRUCTS = {'RawDistributionVector'}


def load(path):
    return json.load(open(path, encoding='utf-8'))


class Dump:
    def __init__(self, j, amap):
        self.ex, self.im, self.amap = j['Exports'], j['Imports'], amap

    def name_of(self, i):
        if i < 0: return self.im[-i - 1]['ObjectName']
        if i > 0: return self.ex[i - 1]['ObjectName']
        return None

    def class_of(self, e):
        return self.name_of(e['ClassIndex'])

    def export(self, i):
        return self.ex[i - 1]

    def by_name(self, name):
        return [e for e in self.ex if e.get('ObjectName') == name][0]


def num(v):
    if isinstance(v, str):
        return float(v.replace('+', ''))
    return float(v)


def fmt(x):
    return ('%.6g' % x) if isinstance(x, float) else str(x)


def vec_text(v):
    return '(X=%s,Y=%s,Z=%s)' % (fmt(num(v['X'])), fmt(num(v['Y'])), fmt(num(v['Z'])))


def table_dist(tbl, vector):
    """A cooked lookup table -> a distribution spec."""
    t = {p['Name']: p for p in tbl}
    get = lambda n, d=0: t[n]['Value'] if n in t else d
    op, count = int(get('Op', 0)), int(get('EntryCount', 1))
    stride = int(get('EntryStride', 3 if vector else 1))
    sub = int(get('SubEntryStride', 0))
    scale, bias = num(get('TimeScale', 0.0)), num(get('TimeBias', 0.0))
    vals = [num(v['Value']) for v in (t['Values']['Value'] if 'Values' in t else [])]
    n = 3 if vector else 1
    if not vals:
        vals = [0.0] * (n * (2 if op == 2 else 1))
        count = 1
    def entry(i):
        e = vals[i * stride:(i + 1) * stride]
        if op == 2:                                   # (random: min, then max, each n wide)
            k = sub or n
            return e[:n], e[k:k + n]
        return e[:n], None
    if count <= 1:
        lo, hi = entry(0)
        if vector:
            if hi is None:
                return {'class': 'DistributionVectorConstant', 'props': {'Constant': '(X=%s,Y=%s,Z=%s)' % tuple(fmt(x) for x in lo)}}
            return {'class': 'DistributionVectorUniform', 'props': {'Min': '(X=%s,Y=%s,Z=%s)' % tuple(fmt(x) for x in lo),
                                                                   'Max': '(X=%s,Y=%s,Z=%s)' % tuple(fmt(x) for x in hi)}}
        if hi is None:
            return {'class': 'DistributionFloatConstant', 'props': {'Constant': fmt(lo[0])}}
        return {'class': 'DistributionFloatUniform', 'props': {'Min': fmt(lo[0]), 'Max': fmt(hi[0])}}
    pts = []
    for i in range(count):
        tm = bias + (i / scale if scale else 0.0)
        lo, hi = entry(i)
        if vector and hi is None:
            pts.append('(InVal=%s,OutVal=(X=%s,Y=%s,Z=%s),InterpMode=CIM_Linear)' % ((fmt(tm),) + tuple(fmt(x) for x in lo)))
        elif vector:
            pts.append('(InVal=%s,OutVal=(v1=(X=%s,Y=%s,Z=%s),v2=(X=%s,Y=%s,Z=%s)),InterpMode=CIM_Linear)'
                       % ((fmt(tm),) + tuple(fmt(x) for x in lo) + tuple(fmt(x) for x in hi)))
        elif hi is None:
            pts.append('(InVal=%s,OutVal=%s,InterpMode=CIM_Linear)' % (fmt(tm), fmt(lo[0])))
        else:
            pts.append('(InVal=%s,OutVal=(X=%s,Y=%s),InterpMode=CIM_Linear)' % (fmt(tm), fmt(lo[0]), fmt(hi[0])))
    cls = ('DistributionVector' if vector else 'DistributionFloat') + ('UniformCurve' if op == 2 else 'ConstantCurve')
    return {'class': cls, 'props': {'ConstantCurve': '(Points=(%s))' % ','.join(pts)}}


def obj_dist(d, e):
    """A distribution kept as an object in the cooked package (particle parameters and the like)."""
    cls = d.class_of(e)
    return {'class': cls, 'props': props(d, e['Data'], cls)}


def value(d, p, owner_cls):
    """One property -> an import-text string, a nested object spec ({"obj": ...}), a distribution ({"dist": ...}) or None."""
    t = p['$type'].split(',')[0].split('.')[-1]
    v = p.get('Value')
    if t == 'StructPropertyData':
        st = p.get('StructType')
        if st in FLOAT_TABLE_STRUCTS or st in VECTOR_TABLE_STRUCTS:
            inner = {q['Name']: q for q in (v or [])}
            ref = inner.get('Distribution', {}).get('Value', 0)
            if ref and ref > 0:
                return {'dist': obj_dist(d, d.export(ref))}
            if 'Table' in inner:
                return {'dist': table_dist(inner['Table']['Value'], st in VECTOR_TABLE_STRUCTS)}
            return None
        if st in ('Vector', 'Rotator') and v:
            q = v[0]['Value']
            if st == 'Vector':
                return vec_text(q)
            return '(Pitch=%s,Yaw=%s,Roll=%s)' % (fmt(num(q['Pitch'])), fmt(num(q['Yaw'])), fmt(num(q['Roll'])))
        if st == 'Box' and v:
            q = v[0]['Value']
            return '(Min=%s,Max=%s,IsValid=1)' % (vec_text(q['Min']), vec_text(q['Max']))
        if st == 'LinearColor' and v:
            q = v[0]['Value']
            return '(R=%s,G=%s,B=%s,A=%s)' % tuple(fmt(num(q[k])) for k in ('R', 'G', 'B', 'A'))
        # a plain struct: its fields as (Name=Value,...)
        parts = []
        for q in (v or []):
            x = value(d, q, owner_cls)
            if isinstance(x, str):
                parts.append('%s=%s' % (q['Name'], x))
        return '(%s)' % ','.join(parts) if parts else None
    if t == 'ArrayPropertyData':
        items = []
        for q in (v or []):
            x = value(d, q, owner_cls)
            if isinstance(x, str):
                items.append(x)
        return '(%s)' % ','.join(items)
    if t == 'ObjectPropertyData':
        if not v:
            return 'None'
        if v < 0:
            name = d.name_of(v)
            if name in d.amap:
                path = d.amap[name]
                return "%s'%s.%s'" % ('Object', path, path.rsplit('/', 1)[1])
            return None                               # (an AC7 asset not mapped: left at its default)
        return None                                   # (an export: modules and emitters are wired by structure)
    if t in ('FloatPropertyData', 'DoublePropertyData'):
        return fmt(num(v))
    if t in ('IntPropertyData', 'Int8PropertyData', 'Int16PropertyData', 'UInt32PropertyData', 'UInt16PropertyData'):
        return str(int(v))
    if t == 'BoolPropertyData':
        return 'True' if v else 'False'
    if t == 'NamePropertyData' or t == 'StrPropertyData':
        return str(v) if v is not None else 'None'
    if t in ('EnumPropertyData',):
        return str(v).split('::')[-1] if v else None
    if t == 'BytePropertyData':
        if v is None:
            return None                               # (an enum byte the dump couldn't name: left at its default)
        if p.get('ByteType') == 'Enum' or (isinstance(v, str) and not v.lstrip('-').isdigit()):
            return str(v).split('::')[-1]
        return str(int(v))
    return None


def props(d, data, cls):
    out = {}
    for p in data or []:
        x = value(d, p, cls)
        if x is not None:
            out[p['Name']] = x
    return out


def module_spec(d, i):
    e = d.export(i)
    cls = d.class_of(e)
    return {'name': e['ObjectName'], 'class': cls, 'props': props(d, e['Data'], cls)}


def system_spec(j, amap):
    d = Dump(j, amap)
    ps = [e for e in d.ex if d.class_of(e) == 'ParticleSystem'][0]
    pp = {p['Name']: p for p in ps['Data']}
    spec = {'name': ps['ObjectName'], 'props': {}, 'emitters': []}
    for k in ('bUseFixedRelativeBoundingBox', 'FixedRelativeBoundingBox', 'bOrientZAxisTowardCamera', 'SecondsBeforeInactive',
              'Delay', 'bUseDelayRange', 'DelayLow', 'WarmupTime', 'bShouldResetPeakCounts'):
        if k in pp:
            x = value(d, pp[k], 'ParticleSystem')
            if isinstance(x, str): spec['props'][k] = x
    for ref in pp['Emitters']['Value']:
        em = d.export(ref['Value'])
        ecls = d.class_of(em)
        ep = {p['Name']: p for p in em['Data']}
        espec = {'name': str(ep.get('EmitterName', {}).get('Value') or em['ObjectName']), 'class': ecls,
                 'props': {k: v for k, v in props(d, [p for p in em['Data'] if p['Name'] not in ('LODLevels', 'EmitterName')], ecls).items()},
                 'lods': []}
        for lref in ep['LODLevels']['Value']:
            lod = d.export(lref['Value'])
            lp = {p['Name']: p for p in lod['Data']}
            lspec = {'props': {}, 'modules': []}
            for k in ('Level', 'bEnabled'):
                if k in lp:
                    x = value(d, lp[k], 'ParticleLODLevel')
                    if isinstance(x, str): lspec['props'][k] = x
            for role, key in (('required', 'RequiredModule'), ('spawn', 'SpawnModule'), ('typedata', 'TypeDataModule')):
                r = lp.get(key, {}).get('Value', 0)
                lspec[role] = module_spec(d, r) if r and r > 0 else None
            for mref in lp.get('Modules', {}).get('Value', []):
                if mref['Value'] and mref['Value'] > 0:
                    lspec['modules'].append(module_spec(d, mref['Value']))
            espec['lods'].append(lspec)
        spec['emitters'].append(espec)
    return spec


def main():
    args = sys.argv[1:]
    src, out = args[0], args[1]
    amap = {}
    for a in args[2:]:
        if a == '--map': continue
        k, _, v = a.partition('=')
        if v: amap[k] = v
    spec = system_spec(load(src), amap)
    json.dump(spec, open(out, 'w', encoding='utf-8'), indent=1)
    n = sum(len(l['modules']) + 2 + (1 if l['typedata'] else 0) for e in spec['emitters'] for l in e['lods'])
    print('%s: %d emitters, %d modules -> %s' % (spec['name'], len(spec['emitters']), n, out))


if __name__ == '__main__':
    main()
