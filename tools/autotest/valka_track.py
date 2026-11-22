"""valka_track.py : VALKA's fight from an autotest run's `valka-track:` / `valka-ev:` lines (the valka suite,
lua/sv_selftest.lua), as numbers and a top-down picture.

  python -X utf8 -I tools/autotest/valka_track.py <run folder or Survival Lua log> [-o <out.svg>] [--label TEXT]

Prints, phase by phase (R her reveal, A round the airfield, B the leg away, C round the new spot): her speed (mean,
share of the time under 500 km/h), her distance from you, how far she ranges (her track's spread round its own centre),
how far her fight's centre moved against yours, where you were off her nose, and her events (orders, LastTGTs,
post-stalls, blinks, railgun shots). The SVG: both tracks from above (hers red, yours blue, the phases marked), her
speed and distance over time underneath. Reads the logs as data only.
"""
import math
import os
import re
import sys

TRACK = re.compile(r'valka-track: ([\d.]+) (\S+) (\S+) her (\S+) (\S+) (\S+) v (\S+) you (\S+) (\S+) (\S+) v (\S+) nose (\S+) hp (\S+)')
EV = re.compile(r'valka-ev: ([\d.]+) (\S+) (\S+)')
PHASES = ['R', 'A', 'B', 'C']
COLOURS = {'R': '#888888', 'A': '#d43c3c', 'B': '#e08a1e', 'C': '#9b3cd4'}


def num(s):
    try:
        return float(s)
    except ValueError:
        return None


def find_log(path):
    if os.path.isfile(path):
        return path
    best = None
    for root, _, files in os.walk(path):
        for f in files:
            if f.startswith('AC8SurvivalMode_lua') and f.endswith('.log'):
                p = os.path.join(root, f)
                if best is None or os.path.getsize(p) > os.path.getsize(best):
                    best = p
    return best


def read(path):
    rows, evs = [], []
    with open(path, encoding='utf-8', errors='replace') as fh:
        for line in fh:
            m = TRACK.search(line)
            if m:
                g = m.groups()
                her = [num(x) for x in g[3:6]]
                you = [num(x) for x in g[7:10]]
                rows.append({'t': float(g[0]), 'ph': g[1], 'st': g[2], 'her': her if None not in her else None,
                             'hv': num(g[6]), 'you': you if None not in you else None, 'yv': num(g[10]),
                             'nose': num(g[11]), 'hp': num(g[12]) if g[12] != 'nil' else None})
                continue
            m = EV.search(line)
            if m:
                evs.append((float(m.group(1)), m.group(2), m.group(3)))
    return rows, evs


def dist(a, b):
    return math.sqrt(sum((a[i] - b[i]) ** 2 for i in range(3)))


def centre(pts):
    n = len(pts)
    return [sum(p[i] for p in pts) / n for i in range(3)] if n else None


def spread(pts):
    c = centre(pts)
    if not c:
        return None
    return math.sqrt(sum(dist(p, c) ** 2 for p in pts) / len(pts))


def ev_kind(e):
    if e.startswith('RE_SV_ValkaTp_'):
        return 'blink'
    k = e.replace('RE_SV_Valka', '')
    return {'Engage': 'orders', 'Turn': 'LastTGT', 'Kulbit': 'post-stall', 'KulbitB': 'post-stall',
            'Cobra': 'post-stall', 'Railgun': 'railgun', 'Hold': 'hold'}.get(k, k)


def summary(rows, evs):
    out = []
    for ph in PHASES:
        R = [r for r in rows if r['ph'] == ph and r['her'] and r['you']]
        if not R:
            continue
        dur = R[-1]['t'] - R[0]['t']
        hv = [r['hv'] for r in R if r['hv'] is not None and r['hv'] >= 0]
        d = sorted(dist(r['her'], r['you']) / 1000 for r in R)
        her_pts, you_pts = [r['her'] for r in R], [r['you'] for r in R]
        path = sum(dist(her_pts[i], her_pts[i - 1]) for i in range(1, len(her_pts))) / 1000
        ypath = sum(dist(you_pts[i], you_pts[i - 1]) for i in range(1, len(you_pts))) / 1000
        nose = [r['nose'] for r in R if r['nose'] is not None and r['nose'] >= 0]
        e = {}
        for t, p, name in evs:
            if p == ph:
                k = ev_kind(name)
                e[k] = e.get(k, 0) + 1
        out.append({
            'phase': ph, 'samples': len(R), 'secs': dur,
            'her_kmh_mean': sum(hv) / len(hv) if hv else None,
            'her_slow_share': sum(1 for v in hv if v < 500) / len(hv) if hv else None,
            'her_kmh_min': min(hv) if hv else None, 'her_kmh_max': max(hv) if hv else None,
            'you_kmh_mean': sum(r['yv'] for r in R if r['yv'] is not None) / len(R),
            'dist_mean_km': sum(d) / len(d), 'dist_median_km': d[len(d) // 2], 'dist_max_km': d[-1],
            'her_spread_km': spread(her_pts) / 1000, 'you_spread_km': spread(you_pts) / 1000,
            'her_centre': centre(her_pts), 'you_centre': centre(you_pts),
            'her_path_km': path, 'you_path_km': ypath,
            'nose_on_share': sum(1 for x in nose if x <= 30) / len(nose) if nose else None,
            'you_behind_share': sum(1 for x in nose if x >= 120) / len(nose) if nose else None,
            'alt_m': (min(r['her'][2] for r in R), max(r['her'][2] for r in R)),
            'events': e,
        })
    return out


def report(S, label):
    lines = [f'VALKA track: {label}']
    for s in S:
        f = lambda x, fmt='%.0f': (fmt % x) if x is not None else '-'
        ev = ', '.join(f'{k} {v}' for k, v in sorted(s['events'].items())) or 'none'
        lines.append(
            f"phase {s['phase']}: {s['secs']:.0f} s, {s['samples']} samples | her speed {f(s['her_kmh_mean'])} km/h "
            f"(min {f(s['her_kmh_min'])}, max {f(s['her_kmh_max'])}; under 500 km/h {f(100 * s['her_slow_share'] if s['her_slow_share'] is not None else None)} %) "
            f"| you {s['you_kmh_mean']:.0f} km/h | her distance from you mean {s['dist_mean_km']:.1f} km, median "
            f"{s['dist_median_km']:.1f}, max {s['dist_max_km']:.1f} | she flew {s['her_path_km']:.1f} km (you "
            f"{s['you_path_km']:.1f}), her track's spread {s['her_spread_km']:.1f} km (yours {s['you_spread_km']:.1f}) | "
            f"you within 30 deg of her nose {f(100 * s['nose_on_share'] if s['nose_on_share'] is not None else None)} %, "
            f"behind her {f(100 * s['you_behind_share'] if s['you_behind_share'] is not None else None)} % | her height "
            f"{s['alt_m'][0]:.0f}-{s['alt_m'][1]:.0f} m | events: {ev}")
    byph = {s['phase']: s for s in S}
    if 'A' in byph and 'C' in byph:
        hm = dist(byph['A']['her_centre'], byph['C']['her_centre']) / 1000
        ym = dist(byph['A']['you_centre'], byph['C']['you_centre']) / 1000
        lines.append(f'the fight moved: your centre {ym:.1f} km from phase A to C, hers {hm:.1f} km '
                     f'({100 * hm / ym if ym > 0.1 else 0:.0f} % of yours)')
    return '\n'.join(lines)


def svg(rows, evs, S, label, out):
    W, H, M = 1100, 1250, 50
    pts = [r['her'] for r in rows if r['her']] + [r['you'] for r in rows if r['you']]
    if not pts:
        return
    xs, ys = [p[0] for p in pts], [p[1] for p in pts]
    x0, x1, y0, y1 = min(xs), max(xs), min(ys), max(ys)
    span = max(x1 - x0, y1 - y0, 2000) * 1.08
    cx, cy = (x0 + x1) / 2, (y0 + y1) / 2
    mapH = W - 2 * M

    def P(p):          # world metres -> map pixels (east right, north up: AC8's -Y is north)
        return (M + (p[0] - cx) / span * mapH + mapH / 2, M + 40 + (p[1] - cy) / span * mapH + mapH / 2)
    o = [f'<svg xmlns="http://www.w3.org/2000/svg" width="{W}" height="{H}" viewBox="0 0 {W} {H}" '
         f'font-family="Segoe UI, Arial, sans-serif" font-size="14">',
         f'<rect width="{W}" height="{H}" fill="#101418"/>',
         f'<text x="{M}" y="32" fill="#eee" font-size="20">VALKA vs you, from above: {label}</text>',
         f'<rect x="{M}" y="{M + 40}" width="{mapH}" height="{mapH}" fill="#161c22" stroke="#333"/>']
    # grid every 5 km
    step = 5000
    gx = math.floor((cx - span / 2) / step) * step
    while gx < cx + span / 2:
        a, b = P((gx, cy - span / 2, 0)), P((gx, cy + span / 2, 0))
        if M <= a[0] <= M + mapH:
            o.append(f'<line x1="{a[0]:.1f}" y1="{M + 40}" x2="{a[0]:.1f}" y2="{M + 40 + mapH}" stroke="#222a33"/>')
        gx += step
    gy = math.floor((cy - span / 2) / step) * step
    while gy < cy + span / 2:
        a = P((cx, gy, 0))
        if M + 40 <= a[1] <= M + 40 + mapH:
            o.append(f'<line x1="{M}" y1="{a[1]:.1f}" x2="{M + mapH}" y2="{a[1]:.1f}" stroke="#222a33"/>')
        gy += step
    # the airfield (Comona's runway, AIRFIELD in sv_core.lua: 16096, -4364 m)
    af = P((16096.39, -4364.14, 0))
    o.append(f'<rect x="{af[0] - 6:.1f}" y="{af[1] - 3:.1f}" width="12" height="6" fill="#7fd47f"/>'
             f'<text x="{af[0] + 9:.1f}" y="{af[1] + 5:.1f}" fill="#7fd47f">airfield</text>')
    # your track (blue) then hers (by phase)
    for key, col_of, width in (('you', lambda ph: '#3c8ad4', 2), ('her', lambda ph: COLOURS.get(ph, '#d43c3c'), 2)):
        seg, last = [], None
        for r in rows:
            p = r[key]
            if not p:
                continue
            q = P(p)
            if last and last[1] == r['ph'] and dist(last[2], p) < 3000:
                seg.append((last[0], q, r['ph']))
            last = (q, r['ph'], p)
        for a, b, ph in seg:
            o.append(f'<line x1="{a[0]:.1f}" y1="{a[1]:.1f}" x2="{b[0]:.1f}" y2="{b[1]:.1f}" stroke="{col_of(ph)}" '
                     f'stroke-width="{width}" stroke-opacity="0.85"/>')
    # blinks (jumps of hers), the phase starts
    for t, ph, name in evs:
        if name.startswith('RE_SV_ValkaTp_'):
            r = min(rows, key=lambda r: abs(r['t'] - t))
            if r['her']:
                q = P(r['her'])
                o.append(f'<circle cx="{q[0]:.1f}" cy="{q[1]:.1f}" r="4" fill="none" stroke="#ffd24a"/>')
    for ph in PHASES:
        R = [r for r in rows if r['ph'] == ph and r['her'] and r['you']]
        if R:
            for key, col in (('her', COLOURS.get(ph)), ('you', '#3c8ad4')):
                q = P(R[0][key])
                o.append(f'<circle cx="{q[0]:.1f}" cy="{q[1]:.1f}" r="6" fill="{col}" stroke="#fff"/>'
                         f'<text x="{q[0] + 8:.1f}" y="{q[1] - 6:.1f}" fill="#fff">{ph}</text>')
    # scale bar
    px5 = 5000 / span * mapH
    o.append(f'<line x1="{M + 20}" y1="{M + 40 + mapH - 20}" x2="{M + 20 + px5:.1f}" y2="{M + 40 + mapH - 20}" stroke="#eee" stroke-width="3"/>'
             f'<text x="{M + 20}" y="{M + 40 + mapH - 28}" fill="#eee">5 km</text>'
             f'<text x="{M + mapH - 330}" y="{M + 62}" fill="#ddd">her: phase A red, B orange, C purple; you: blue; '
             f'yellow rings: her blinks</text>')
    # speed and distance over time
    gy0, gh = M + 60 + mapH, H - (M + 60 + mapH) - 40
    t0, t1 = rows[0]['t'], rows[-1]['t']
    tx = lambda t: M + (t - t0) / max(1, t1 - t0) * mapH
    o.append(f'<rect x="{M}" y="{gy0}" width="{mapH}" height="{gh}" fill="#161c22" stroke="#333"/>')
    vmax = 2400.0
    dmax = max([dist(r['her'], r['you']) / 1000 for r in rows if r['her'] and r['you']] + [5])
    for key, col, f in (('hv', '#d43c3c', lambda r: r['hv'] / vmax if r['hv'] is not None and r['hv'] >= 0 else None),
                        ('yv', '#3c8ad4', lambda r: r['yv'] / vmax if r['yv'] is not None and r['yv'] >= 0 else None),
                        ('d', '#e8e8e8', lambda r: dist(r['her'], r['you']) / 1000 / dmax if r['her'] and r['you'] else None)):
        prev = None
        for r in rows:
            v = f(r)
            if v is None:
                prev = None
                continue
            q = (tx(r['t']), gy0 + gh - v * gh)
            if prev:
                o.append(f'<line x1="{prev[0]:.1f}" y1="{prev[1]:.1f}" x2="{q[0]:.1f}" y2="{q[1]:.1f}" stroke="{col}" stroke-width="1.5"/>')
            prev = q
    y500 = gy0 + gh - 500 / vmax * gh
    o.append(f'<line x1="{M}" y1="{y500:.1f}" x2="{M + mapH}" y2="{y500:.1f}" stroke="#d43c3c" stroke-dasharray="4 4" stroke-opacity="0.6"/>')
    o.append(f'<text x="{M + 6}" y="{gy0 + 18}" fill="#ddd">red: her speed, blue: yours (0-{vmax:.0f} km/h; dashed: 500); '
             f'white: her distance from you (0-{dmax:.0f} km); ticks: her events</text>')
    for t, ph, name in evs:
        k = ev_kind(name)
        col = {'LastTGT': '#ffd24a', 'orders': '#7fd47f', 'post-stall': '#ff6ad5', 'blink': '#ffffff', 'railgun': '#ff3030'}.get(k)
        if col:
            x = tx(t)
            o.append(f'<line x1="{x:.1f}" y1="{gy0 + gh - 12}" x2="{x:.1f}" y2="{gy0 + gh}" stroke="{col}"/>')
    o.append(f'<text x="{M}" y="{H - 14}" fill="#aaa">event ticks: green her orders, yellow LastTGT, pink post-stall, white blink, red railgun</text>')
    for ph in PHASES:
        R = [r for r in rows if r['ph'] == ph]
        if R:
            x = tx(R[0]['t'])
            o.append(f'<line x1="{x:.1f}" y1="{gy0}" x2="{x:.1f}" y2="{gy0 + gh}" stroke="#555"/><text x="{x + 4:.1f}" y="{gy0 + 36}" fill="#aaa">{ph}</text>')
    o.append('</svg>')
    with open(out, 'w', encoding='utf-8') as fh:
        fh.write('\n'.join(o))


def main():
    args = sys.argv[1:]
    if not args or args[0] in ('-h', '--help'):
        print(__doc__)
        return 2
    out = None
    label = os.path.basename(os.path.normpath(args[0]))
    if '-o' in args:
        out = args[args.index('-o') + 1]
    if '--label' in args:
        label = args[args.index('--label') + 1]
    log = find_log(args[0])
    if not log:
        print('no Survival Lua log found in', args[0])
        return 1
    rows, evs = read(log)
    if not rows:
        print('no valka-track lines in', log)
        return 1
    S = summary(rows, evs)
    print(report(S, label))
    if out:
        svg(rows, evs, S, label, out)
        print('picture:', out)
    return 0


if __name__ == '__main__':
    sys.exit(main())
