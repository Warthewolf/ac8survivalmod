"""hud_layout.py : print a widget blueprint's layout (stock zen packages pulled with tools/get_stock.sh).

  python hud_layout.py <pkg.uasset>... [--root 3840x2160] [--brief]

Walks WidgetTree.RootWidget -> panel Slots -> slot.Content and prints one line per widget: class, name, visibility,
opacity, render transform, the slot's layout and, for canvas children, the rectangle on the design canvas (root size
--root; the HUD4K widgets are laid out for 3840x2160). Texts show their default string, font (typeface/size) and
colour; images their brush size and colour; embedded widget blueprints show which package they come from.

Unversioned properties leave out anything equal to the class default, so missing fields are filled from the UMG
defaults below (CanvasPanelSlot offsets 0,0,100,30, anchors 0,0, alignment 0,0; TextBlock white; visibility Visible).
A widget-blueprint instance (sub-widget) has its blueprint's own variables first in the property index, so its
UserWidget fields are read with a shift: the one where its Slot points back at the slot holding it.
"""
import os, pickle, struct, sys
HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, os.path.join(HERE, '..', 'scripts'))
from zen import Zen
import uprop, ue
# UE5.4 structs stored as raw binary (no property header): FSlateBrush.ImageSize, UVRegion
uprop.NATIVE_SIZE.update({'DeprecateSlateVector2D': 8, 'Box2f': 17, 'Vector2f': 8})

SO =pickle.load(open(os.path.join(HERE, '..', 'scriptobjs.pkl'), 'rb'))
VIS = ['Visible', 'Collapsed', 'Hidden', 'HitTestInvisible', 'SelfHitTestInvisible']
SKIP = ('MovieScene', 'WidgetAnimation', 'WidgetBlueprintGeneratedClass', 'WidgetTree', 'Default__')
SLOT_DEFAULT = dict(off=(0.0, 0.0, 100.0, 30.0), amin=(0.0, 0.0), amax=(0.0, 0.0), align=(0.0, 0.0), auto=False, z=0)


def f32(v): return struct.unpack('<f', v[2])[0]
def i32(v): return struct.unpack('<i', v[2])[0]
def vec2(v): return struct.unpack('<2d', v[2])


def props(v):
    """('struct', name, [(idx, nm, zero, val)]) -> {nm: val or 'ZERO'}"""
    return {p[1]: ('ZERO' if p[2] else p[3]) for p in v[2]} if v and v[0] == 'struct' else {}


def ftext(raw):
    """Source string of a serialized FText (Base history), or ''."""
    try:
        o = 4; hist = struct.unpack_from('<b', raw, o)[0]; o += 1
        def fstr():
            nonlocal o
            n = struct.unpack_from('<i', raw, o)[0]; o += 4
            if n == 0: return ''
            if n < 0: s = raw[o:o - 2 * n].decode('utf-16-le')[:-1]; o += -2 * n; return s
            s = raw[o:o + n - 1].decode('latin1'); o += n; return s
        if hist == 0: fstr(); fstr(); return fstr()
        if hist == -1:
            has = struct.unpack_from('<i', raw, o)[0]; o += 4
            return fstr() if has else ''
        return f'<text history {hist}>'
    except Exception:
        return '?'


class Pkg:
    def __init__(self, path):
        self.z = z = Zen(path); self.c = uprop.Ctx(z.d, z.names)
        self.name = os.path.splitext(os.path.basename(path))[0]
        self.imp_pkgs = []
        if z.imp_pkg_names_off and z.imp_pkg_names_off < z.header_size:
            try: self.imp_pkgs, _ = z.read_namebatch(z.imp_pkg_names_off)
            except Exception: self.imp_pkgs = []
        self.slot_of = {}                          # export index of a widget -> its slot export index
        self.parsed = {}

    def cls(self, i):
        v = self.z.exports[i]['cls']; t = v >> 62
        if t == 1: return SO.get(v, 'script?%x' % v)
        if t == 2:
            k = (v & ((1 << 62) - 1)) >> 32
            return 'BP:' + (self.imp_pkgs[k].split('/')[-1] if k < len(self.imp_pkgs) else f'pkg{k}')
        if t == 0: return 'export:%d' % v
        return 'null'

    def imp(self, i):
        v = self.z.imports[i] if 0 <= i < len(self.z.imports) else None
        return SO.get(v, 'imp%d' % i) if v is not None else 'imp?'

    def ref(self, v):
        """('obj', n) -> ('exp', idx) | ('imp', name) | None"""
        if not v or v == 'ZERO' or v[0] != 'obj' or v[1] == 0: return None
        return ('exp', v[1] - 1) if v[1] > 0 else ('imp', self.imp(-v[1] - 1))

    def read(self, i, schema):
        e = self.z.exports[i]
        try:
            v, o = uprop.read_struct(self.c, self.z.header_size + e['off'], schema)
            return props(v), None
        except Exception as ex:
            return {}, f'{type(ex).__name__} {ex}'

    def widget_props(self, i):
        if i in self.parsed: return self.parsed[i]
        c = self.cls(i)
        if not c.startswith('BP:'):
            p, err = self.read(i, c)
        else:                                      # sub-widget: shift UserWidget's indices past the BP's own props
            p, err = {}, 'no shift found'
            sc = ue.U.schema('UserWidget'); want = self.slot_of.get(i)
            for k in range(0, 400):
                ue.U._shift = None
                shifted = {idx + k: t for idx, t in sc.items()}
                try:
                    v, _ = read_shifted(self.c, self.z.header_size + self.z.exports[i]['off'], shifted)
                except Exception:
                    continue
                q = props(v); r = self.ref(q.get('Slot'))
                if want is None or (r and r == ('exp', want)):
                    p, err = q, None; break
        self.parsed[i] = (p, err)
        return p, err


def read_shifted(c, o, sc):
    items, o = uprop._hdr_read(c, o); out = []
    for idx, z in items:
        nm, t = sc[idx]
        if z: out.append((idx, nm, True, None)); continue
        v, o = uprop.read_value(c, o, t); out.append((idx, nm, False, v))
    return ('struct', 'UserWidget*', out), o


def slot_info(pk, si):
    """Slot export -> (class, layout dict, content export index)."""
    sc = pk.cls(si); p, err = pk.read(si, sc)
    cont = pk.ref(p.get('Content'))
    L = dict(cls=sc, err=err)
    if sc == 'CanvasPanelSlot':
        d = dict(SLOT_DEFAULT); ld = props(p.get('LayoutData'))
        if ld:
            om = props(ld.get('Offsets')) if ld.get('Offsets') not in (None, 'ZERO') else {}
            off = list(d['off'])
            for k, n in enumerate(('Left', 'Top', 'Right', 'Bottom')):
                if n in om: off[k] = 0.0 if om[n] == 'ZERO' else f32(om[n])
            if ld.get('Offsets') == 'ZERO': off = [0.0] * 4
            d['off'] = tuple(off)
            an = props(ld.get('Anchors')) if ld.get('Anchors') not in (None, 'ZERO') else {}
            if 'Minimum' in an: d['amin'] = (0.0, 0.0) if an['Minimum'] == 'ZERO' else vec2(an['Minimum'])
            if 'Maximum' in an: d['amax'] = (0.0, 0.0) if an['Maximum'] == 'ZERO' else vec2(an['Maximum'])
            if 'Alignment' in ld: d['align'] = (0.0, 0.0) if ld['Alignment'] == 'ZERO' else vec2(ld['Alignment'])
        if 'bAutoSize' in p: d['auto'] = p['bAutoSize'] != 'ZERO' and p['bAutoSize'][2] != b'\x00'
        if 'ZOrder' in p: d['z'] = 0 if p['ZOrder'] == 'ZERO' else i32(p['ZOrder'])
        L.update(d)
    else:
        for k in ('Padding', 'Size', 'HorizontalAlignment', 'VerticalAlignment'):
            if k in p: L[k] = brief(p[k])
    return L, (cont[1] if cont and cont[0] == 'exp' else None)


def brief(v):
    if v == 'ZERO': return '0'
    if not isinstance(v, tuple): return str(v)
    k = v[0]
    if k == 'raw':
        if v[1] == 'Float': return '%g' % f32(v)
        if v[1] == 'Int': return str(i32(v))
        if v[1] == 'Bool': return str(v[2] != b'\x00')
        return v[2].hex()
    if k == 'enum': return brief(v[2]) if v[2][0] != 'raw' else str(v[2][2][0])
    if k == 'name': return v[1]
    if k == 'native':
        n = len(v[2]) // 8 if v[1] in ('Vector2D', 'Vector', 'Vector4') else len(v[2]) // 4
        f = '<%dd' % n if v[1] in ('Vector2D', 'Vector', 'Vector4') else '<%df' % n
        return '(' + ','.join('%g' % x for x in struct.unpack(f, v[2])) + ')'
    if k == 'struct': return '{' + ' '.join(f'{p[1]}={brief("ZERO" if p[2] else p[3])}' for p in v[2]) + '}'
    if k == 'obj': return f'obj{v[1]}'
    return str(v)[:60]


def color(v):
    sc = props(v) if v not in (None, 'ZERO') else {}
    c = sc.get('SpecifiedColor')
    if c is None: return None
    if c == 'ZERO': return '(0,0,0,0)'
    return '(' + ','.join('%.2f' % x for x in struct.unpack('<4f', c[2])) + ')'


def rect(L, parent):
    """Canvas child rectangle (x, y, w, h) in design units, or None (auto size / unknown)."""
    px, py, pw, ph = parent
    (l, t, r, b), (ax0, ay0), (ax1, ay1), (alx, aly) = L['off'], L['amin'], L['amax'], L['align']
    if ax0 == ax1: w = r; x = px + ax0 * pw + l - alx * w
    else: x = px + ax0 * pw + l; w = (px + ax1 * pw - r) - x
    if ay0 == ay1: h = b; y = py + ay0 * ph + t - aly * h
    else: y = py + ay0 * ph + t; h = (py + ay1 * ph - b) - y
    return (x, y, w, h)


def describe(pk, i, p):
    c = pk.cls(i); out = []
    vis = p.get('Visibility')
    if vis is not None: out.append('vis=' + (VIS[0] if vis == 'ZERO' else VIS[vis[2][2][0]] if vis[0] == 'enum' and vis[2][0] == 'raw' and vis[2][2][0] < 5 else brief(vis)))
    if 'RenderOpacity' in p: out.append('opacity=' + brief(p['RenderOpacity']))
    if 'RenderTransform' in p: out.append('xform=' + brief(p['RenderTransform']))
    if 'Text' in p and p['Text'] != 'ZERO': out.append('text=' + repr(ftext(p['Text'][1])))
    if 'TextID' in p: out.append('textID=' + brief(p['TextID']))
    if 'Font' in p:
        f = props(p['Font'])
        fo = pk.ref(f.get('FontObject'))
        out.append('font=%s/%s %s%s' % (fo[1] if fo and fo[0] == 'imp' else (fo and 'exp') or 'default',
                                       brief(f.get('TypefaceFontName', ('name', '-', 0))),
                                       brief(f['Size']) if 'Size' in f else '24',
                                       (' spacing=' + brief(f['LetterSpacing'])) if 'LetterSpacing' in f else ''))
    if 'ColorAndOpacity' in p and c in ('TextBlock', 'LiveLocalizeTextBlock', 'Image'):
        out.append('color=' + (color(p['ColorAndOpacity']) if c != 'Image' else brief(p['ColorAndOpacity'])))
    if 'Justification' in p: out.append('justify=' + brief(p['Justification']))
    if c == 'Image' and 'Brush' in p:
        b = props(p['Brush']); res = pk.ref(b.get('ResourceObject'))
        out.append('brush=%s size=%s' % (res[1] if res and res[0] == 'imp' else '-', brief(b.get('ImageSize', 'ZERO')) if 'ImageSize' in b else '(32,32)'))
    if c == 'SizeBox':
        for k in ('WidthOverride', 'HeightOverride'):
            if k in p: out.append(f'{k}={brief(p[k])}')
    if c == 'WidgetSwitcher' and 'ActiveWidgetIndex' in p: out.append('active=' + brief(p['ActiveWidgetIndex']))
    if c == 'ScaleBox':
        for k in ('Stretch', 'UserSpecifiedScale'):
            if k in p: out.append(f'{k}={brief(p[k])}')
    return ' '.join(out)


def walk(pk, i, parent_rect, depth, lines, brief_mode, seen):
    if i in seen: lines.append('  ' * depth + f'(loop {i})'); return
    seen.add(i)
    p, err = pk.widget_props(i)
    c = pk.cls(i); e = pk.z.exports[i]
    lines.append('  ' * depth + f'{c} {e["name"]}  ' + describe(pk, i, p) + (f'  [props: {err}]' if err and not brief_mode else ''))
    for s in (p.get('Slots') or ('arr', []))[1] if p.get('Slots') not in (None, 'ZERO') else []:
        r = pk.ref(s)
        if not r or r[0] != 'exp': continue
        L, child = slot_info(pk, r[1])
        if child is None: continue
        if L['cls'] == 'CanvasPanelSlot':
            rc = rect(L, parent_rect) if parent_rect else None
            lay = 'anch=(%g,%g)-(%g,%g) off=(%g,%g,%g,%g) align=(%g,%g)%s z=%d' % (L['amin'] + L['amax'] + L['off'] + L['align'] + (' auto' if L['auto'] else '', L['z']))
            if rc: lay += '  => x=%.0f y=%.0f w=%.0f h=%.0f' % rc + (' (auto size: real w/h come from the content)' if L['auto'] else '')
        else:
            rc = None
            lay = L['cls'] + ' ' + ' '.join(f'{k}={v}' for k, v in L.items() if k not in ('cls', 'err'))
        lines.append('  ' * (depth + 1) + '@ ' + lay)
        walk(pk, child, rc, depth + 1, lines, brief_mode, seen)     # auto size: the offsets' size is the estimate


def layout(path, root=(3840.0, 2160.0), brief_mode=False):
    pk = Pkg(path); z = pk.z
    for i, e in enumerate(z.exports):         # map each widget to its slot first (sub-widgets need it)
        c = pk.cls(i)
        if c.endswith('Slot') and not c.startswith('BP:'):
            p, _ = pk.read(i, c); r = pk.ref(p.get('Content'))
            if r and r[0] == 'exp': pk.slot_of[r[1]] = i
    lines = [f'=== {pk.name}']
    trees = [i for i, e in enumerate(z.exports) if pk.cls(i) == 'WidgetTree']
    for t in trees:
        p, err = pk.read(t, 'WidgetTree'); r = pk.ref(p.get('RootWidget'))
        owner = z.exports[z.exports[t]['outer'] - 1]['name'] if 0 < z.exports[t]['outer'] <= len(z.exports) else '?'
        if not r or r[0] != 'exp':
            lines.append(f'(WidgetTree {t} of {owner}: no root widget{": " + err if err else ""})'); continue
        if len(trees) > 1: lines.append(f'-- tree of {owner}')
        walk(pk, r[1], (0.0, 0.0) + root, 0, lines, brief_mode, set())
    subs = sorted({pk.cls(i)[3:] for i in range(len(z.exports)) if pk.cls(i).startswith('BP:')})
    if subs: lines.append('embeds: ' + ', '.join(subs))
    return '\n'.join(lines)


def main():
    sys.stdout.reconfigure(encoding='utf-8')               # default texts can be Japanese
    args =[a for a in sys.argv[1:] if not a.startswith('--')]
    root = (3840.0, 2160.0); brief_mode = '--brief' in sys.argv
    for a in sys.argv[1:]:
        if a.startswith('--root'):
            w, h = a.split('=', 1)[1].split('x') if '=' in a else sys.argv[sys.argv.index(a) + 1].split('x')
            root = (float(w), float(h))
    for p in args:
        if p.count('x') == 1 and p.replace('x', '').replace('.', '').isdigit(): continue
        print(layout(p, root, brief_mode)); print()


if __name__ == '__main__':
    main()
