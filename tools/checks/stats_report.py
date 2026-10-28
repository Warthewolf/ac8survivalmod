"""stats_report.py <AC8SurvivalMode_lua.log> [more logs] : the behaviour roadmap's seven measurements from test logs
(tools/re/BEHAVIOUR_DIRECTOR.md, unit 1; Scripts/sv_stats.lua writes the lines). Read only. Prints each run's
"stats: run over" line as a table against the behaviour thesis' targets, one row per "stats: round" line, the
"kill-time:" lines' time to kill over every run, and the "death:", "director:" and "spawn index:" lines; P5's tail
watch (unit 2): the run line's Veteran+ figures, the "tailed:" episodes by tier and by the provoke values they flew (an
A/B of the live provoke), and the "provoke:" writes; P4's intensity director (unit 7): its "intensity:" round lines and
how often it held a wave, pushed a comfortable player and eased the spikes' level. Works on a friend's release log as
well (none of these lines is TEST ONLY) and on UE4SS.log (the same lines behind its tag).
Exit 1 when a file has no measurement lines at all.
"""
import re
import statistics
import sys

# the thesis' targets, as sv_stats.lua's run line states them
TARGETS = {
    'ttk': ('20-40 s', lambda v: 'LOW' if v < 20 else 'HIGH' if v > 40 else 'ok'),
    'tailed': ('8 s+', lambda v: 'ok' if v >= 8 else 'LOW'),
    'special': ('5-8 min', lambda v: 'SHORT' if v < 300 else 'LONG' if v > 480 else 'ok'),
    'missiles': ('under 40', lambda v: 'ok' if v < 40 else 'HIGH'),
    'damage': ('varied', lambda v: 'ok' if v <= 70 else 'ONE-SIDED'),
    'tactics': ('3-6 a round', lambda v: 'LOW' if v < 3 else 'HIGH' if v > 6 else 'ok'),
    'behind': ('under 70 %', lambda v: 'ok' if v < 70 else 'HIGH'),
}
KINDS = ('stats: run over', 'stats: round', 'kill-time:', 'death:', 'director:', 'spawn index:', 'tailed:', 'provoke:',
         'intensity:')


def secs(text):
    """'12 s' -> 12.0, '-' -> None"""
    m = re.match(r'(-?[\d.]+) s$', text.strip())
    return float(m.group(1)) if m else None


def pct(text):
    m = re.match(r'([\d.]+)%$', text.strip())
    return float(m.group(1)) if m else None


def grab(pattern, line, default=None):
    m = re.search(pattern, line)
    return m.groups() if m else default


def lines_of(path):
    """every measurement line in the file, from its kind on (a time stamp or UE4SS's tag before it is dropped)"""
    out = []
    with open(path, encoding='utf-8', errors='replace') as f:
        for raw in f:
            raw = raw.rstrip('\r\n')
            for kind in KINDS:
                at = raw.find(kind)
                if at >= 0:
                    out.append(raw[at:])
                    break
    return out


def verdict(key, value):
    if value is None:
        return '-'
    return TARGETS[key][1](value)


def run_table(line):
    """the seven metrics of one 'stats: run over' line: (number, name, value text, target, verdict)"""
    how, r0, r1 = grab(r'stats: run over \((.*?)\): rounds (\d+)-(\d+);', line, ('?', '?', '?'))
    rows = []
    a, b, ttk, n = grab(r'time to kill rounds (\d+)-(\d+) median (\S+(?: s)?) \(n (\d+)', line, ('?', '?', '-', '0'))
    v = secs(ttk)
    rows.append((1, f'time to kill, ordinary fighters, rounds {a}-{b}', f'{ttk} (n {n})', 'ttk', verdict('ttk', v)))
    ai, nai, geo, ngeo = grab(r'AI Provoke median (\S+(?: s)?) \(n (\d+)\), geometric median (\S+(?: s)?) \(n (\d+)\)', line,
                              ('-', '0', '-', '0'))
    rows.append((2, 'tailed enemy survival, Veteran+ (AI Provoke)', f'{ai} (n {nai})', 'tailed', verdict('tailed', secs(ai))))
    rows.append((2, '  (geometric: you within the tail cone)', f'{geo} (n {ngeo})', 'tailed', verdict('tailed', secs(geo))))
    # (the still-up and already-defending counts came with the review of unit 2: optional, for an earlier log)
    tw = grab(r'tail watch Veteran\+: died after median (\S+(?: s)?) on your tail \(n (\d+)\), (\S+(?: s)?) after its Provoke '
              r'\(n (\d+)\), escaped (\d+) \(held median (\S+(?: s)?)\)(?:, still up at the end (\d+))?, Provoke after median '
              r'(\S+(?: s)?) \(none in (\d+)(?:, already defending (\d+))?\), blackouts (\d+)', line)
    if tw:
        rows.append((2, '  tail watch Veteran+ (4 Hz): died, tailed', f'{tw[0]} (n {tw[1]}); {tw[2]} after Provoke (n {tw[3]})',
                     'tailed', verdict('tailed', secs(tw[0]))))
        rows.append((2, '  (tail watch: escaped, held; still up)', f'{tw[4]} (held {tw[5]}); still up {tw[6] or 0}', 'tailed', '-'))
        # (Provoke after: fresh reactions only; "already": it was defending when you got behind it)
        rows.append((2, '  (watch: Provoke after; none; already)', f'{tw[7]}; none {tw[8]}; already {tw[9] or 0}; '
                     f'blackouts {tw[10]}', 'tailed', '-'))
    sp = (grab(r'special rounds (.*?) \[5-8 min\]', line) or ('none',))[0]
    lens = [float(x) for x in re.findall(r'round \d+ \S+ (\d+) s', sp)]
    worst = [verdict('special', x) for x in lens]
    rows.append((3, 'special round length', sp, 'special',
                 ('ok' if worst and all(w == 'ok' for w in worst) else ', '.join(sorted(set(worst))) if worst else '-')))
    ml = (grab(r'missiles left at the end (\S+)', line) or ('?',))[0].rstrip(';')
    rows.append((4, 'missiles left (at death, else at the end)', ml, 'missiles', verdict('missiles', float(ml) if ml.isdigit() else None)))
    dmg = grab(r'damage taken (\d+) HP: missiles (\S+), gun/close (\S+), unknown (\S+), brackets (\d+)', line)
    if dmg:
        shares = [x for x in (pct(dmg[1].rstrip(',')), pct(dmg[2].rstrip(',')), pct(dmg[3].rstrip(','))) if x is not None]
        rows.append((5, 'damage sources', f'{dmg[0]} HP: msl {dmg[1]} gun/close {dmg[2]} unknown {dmg[3]} brackets {dmg[4]}',
                     'damage', verdict('damage', max(shares) if shares else None)))
    else:
        rows.append((5, 'damage sources', '?', 'damage', '-'))
    tac = grab(r'director tactics per round avg ([\d.]+) \((\d+) in (\d+) rounds\)', line)
    rows.append((6, 'director tactics per round', f'{tac[0]} ({tac[1]} in {tac[2]} rounds)' if tac else '?', 'tactics',
                 verdict('tactics', float(tac[0])) if tac and int(tac[2]) > 0 else '-'))
    beh = grab(r'kills from behind (\S+) \((\d+)/(\d+)\)', line)
    rows.append((7, 'kills from behind', f'{beh[0]} ({beh[1]}/{beh[2]})' if beh else '?', 'behind',
                 verdict('behind', pct(beh[0])) if beh else '-'))
    return how, r0, r1, rows


def round_row(line):
    m = re.match(r'stats: round (\d+) \(([^,]*), ([^,]*?)(?: (\d+) s)?, (\d+) players?\)( \(cut short: (.*?)\))?:', line)
    if not m:
        return None
    ttk = (grab(r'time to kill since engaged median (\S+(?: s)?) \(n (\d+)\)', line) or ('-', '0'))
    if 'ordinary fighters ?' in line:
        ttk = ('joiner', '-')
    return {
        'round': int(m.group(1)), 'tier': m.group(2), 'kind': m.group(3), 'cut': m.group(7) or '',
        'len': (grab(r'length (\d+) s', line) or ('?',))[0],
        'ttk': f'{ttk[0]} (n {ttk[1]})',
        'tail': (grab(r'AI Provoke median (\S+(?: s)?) \(', line) or ('-',))[0],
        'behind': '/'.join(grab(r'kills from behind (\d+)/(\d+)', line) or ('?', '?')),
        'msl': (grab(r'missiles left (\S+), fired', line) or ('?',))[0],
        'tac': (grab(r'director tactics (\d+) \(', line) or ('?',))[0],
        'watch': (grab(r'tail watch: \d+ episodes? \(Veteran\+ \d+\): died after median (\S+(?: s)?) \(', line) or ('-',))[0],
    }


def tailed_lines(ls):
    """P5's tail watch: its "tailed:" episodes by tier and by the provoke values in force (Survival's write or the
    game's own row: an A/B of the live provoke), and the "provoke:" writes"""
    eps = []
    for l in ls:
        if not l.startswith('tailed:'):
            continue
        m = re.search(r'\(([^,()]*), ([^,()]*)(?:, k \d+)?, rank \S+, AI level \S+\): provoke (\S+) deg / (\S+) s \(([^)]*)\)', l)
        if not m:
            continue
        died = re.search(r'; died ([\d.]+) s after', l)
        esc = re.search(r'; escaped after ([\d.]+) s', l)
        up = re.search(r'; still up when the run ended \([^)]*\), ([\d.]+) s on its tail', l)
        react = re.search(r'Provoke after ([\d.]+) s', l)
        pre = re.search(r'already in (\S+) when you got behind it', l)       # (defending before: no reaction of its own)
        eps.append({'tier': m.group(2), 'values': f'{m.group(3)} deg / {m.group(4)} s ({m.group(5)})',
                    'died': float(died.group(1)) if died else None, 'esc': float(esc.group(1)) if esc else None,
                    'up': float(up.group(1)) if up else None, 'pre': pre.group(1) if pre else None,
                    'react': float(react.group(1)) if react else None, 'blackout': 'Blackout ' in l})
    if eps:
        print(f'\ntailed lines: {len(eps)} (the tail watch: you on an enemy\'s tail, 4 Hz)')

        def table(key, title):
            groups = {}
            for e in eps:
                groups.setdefault(e[key], []).append(e)
            # (Provoke after: the fresh reactions only; none: fresh episodes without one; already: defending at once)
            print(f'  {title:<34} {"n":>3} {"died":>4} {"died after":>11} {"escaped":>7} {"up":>3} {"Provoke after":>13} '
                  f'{"none":>4} {"already":>7} blackouts')
            for k in sorted(groups):
                g = groups[k]
                d = [e['died'] for e in g if e['died'] is not None]
                r = [e['react'] for e in g if e['react'] is not None and e['pre'] is None]
                med = lambda v: f'{statistics.median(v):.1f} s' if v else '-'
                print(f'  {k:<34} {len(g):>3} {len(d):>4} {med(d):>11} {sum(1 for e in g if e["esc"] is not None):>7} '
                      f'{sum(1 for e in g if e["up"] is not None):>3} {med(r):>13} '
                      f'{sum(1 for e in g if e["react"] is None and e["pre"] is None):>4} '
                      f'{sum(1 for e in g if e["pre"] is not None):>7} {sum(1 for e in g if e["blackout"])}')
        table('tier', 'tier')
        table('values', 'provoke in force')
    pv = [l for l in ls if l.startswith('provoke:')]
    if pv:
        print(f'\nprovoke lines: {len(pv)} (the live provoke written, once per tier and spike level)')
        for l in pv:
            print('  ' + l[:220])


INT_ROUND = re.compile(r"intensity: round (\d+): you avg (\d+), peak (\d+), above (\d+) for (\d+) s; comfort avg (\d+)"
                       r"(?:; held (\d+) \((\d+) s\), pushes (\d+))?; level (\d+)(?: \(the spikes' (\d+)(?:, the host's)?\))?$")


def intensity_lines(ls):
    """P4's intensity director: its round lines (your intensity and comfort, the host's holds and pushes, the level the
    enemies flew) and its decisions: holds, pushes (and the ones held back), the level eased and back"""
    ints = [l for l in ls if l.startswith('intensity:')]
    if not ints:
        return
    holds = sum(1 for l in ints if re.match(r'intensity: round \d+: held \d+ s', l))
    refused = sum(1 for l in ints if l.startswith('intensity: hold not now'))
    pushed = sum(1 for l in ints if re.search(r' comfortable \d+ s \([^)]*\): (?!no push|nothing sent)', l))
    nopush = sum(1 for l in ints if re.search(r' comfortable \d+ s \([^)]*\): (no push|nothing sent)', l))
    down = sum(1 for l in ints if re.search(r': the room above \d+ for \d+ s of fighting', l))
    up = sum(1 for l in ints if re.search(r': the room below \d+ for \d+ s of fighting', l))
    print(f'\nintensity lines: {len(ints)}: holds {holds} (not now {refused}), pushes {pushed} (held back {nopush}), '
          f'level eased {down}, back up {up}')
    rows = [m for m in (INT_ROUND.match(l) for l in ints) if m]
    if rows:
        print(f'  {"round":>5} {"avg":>4} {"peak":>4} {"hot s":>5} {"comfort":>7} {"held":>4} {"held s":>6} {"pushes":>6} level')
        for m in rows:
            lv = m.group(10) + (f' (spikes {m.group(11)})' if m.group(11) else '')
            print(f'  {m.group(1):>5} {m.group(2):>4} {m.group(3):>4} {m.group(5):>5} {m.group(6):>7} {m.group(7) or "-":>4} '
                  f'{m.group(8) or "-":>6} {m.group(9) or "-":>6} {lv}')


def report(path):
    ls = lines_of(path)
    print(f'stats_report: {path}: {len(ls)} measurement lines')
    if not ls:
        return False
    runs = [l for l in ls if l.startswith('stats: run over')]
    for i, l in enumerate(runs, 1):
        how, r0, r1, rows = run_table(l)
        print(f'\nrun {i} ({how}), rounds {r0}-{r1}')
        print(f'  {"#":<2} {"metric":<46} {"value":<48} {"target":<12} verdict')
        for num, name, value, key, v in rows:
            print(f'  {num:<2} {name:<46} {value[:48]:<48} {TARGETS[key][0]:<12} {v}')
    rounds = [r for r in (round_row(l) for l in ls if l.startswith('stats: round')) if r]
    if rounds:
        print('\nrounds')
        print(f'  {"round":>5} {"tier":<10} {"kind":<12} {"length":>7} {"time to kill":<16} {"tailed":<8} {"watch":<8} '
              f'{"behind":<7} {"msl left":<8} {"tactics":<7} cut short')
        for r in rounds:
            print(f'  {r["round"]:>5} {r["tier"]:<10} {r["kind"]:<12} {r["len"] + " s":>7} {r["ttk"]:<16} {r["tail"]:<8} '
                  f'{r["watch"]:<8} {r["behind"]:<7} {r["msl"]:<8} {r["tac"]:<7} {r["cut"]}')
    kills = [l for l in ls if l.startswith('kill-time:')]
    if kills:
        ttk = []
        for l in kills:
            m = re.search(r'round (\d+)(?:, k \d+)?, ordinary\): up \S+ s, engaged (\S+ s|-)', l)
            if m and 7 <= int(m.group(1)) <= 12 and l.rstrip().find('; by you') >= 0:
                v = secs(m.group(2))
                if v is not None:
                    ttk.append(v)
        med = f'{statistics.median(ttk):.0f} s' if ttk else '-'
        print(f'\nkill-time lines: {len(kills)}; your ordinary fighters in rounds 7-12, every run: median {med} (n {len(ttk)}) '
              f'[target {TARGETS["ttk"][0]}] {verdict("ttk", statistics.median(ttk) if ttk else None)}')
    deaths = [l for l in ls if l.startswith('death:')]
    if deaths:
        print(f'\ndeath lines: {len(deaths)}')
        for l in deaths:
            print('  ' + l[:200])
    dirs = [l for l in ls if l.startswith('director:')]
    if dirs:
        count = {}
        for l in dirs:
            m = re.search(r'\+\d+ s: (\S+) on ', l)
            if m:
                count[m.group(1)] = count.get(m.group(1), 0) + 1
        print(f'\ndirector lines: {len(dirs)}: ' + ', '.join(f'{k} x{v}' for k, v in sorted(count.items())))
    tailed_lines(ls)
    intensity_lines(ls)
    idx = [l for l in ls if l.startswith('spawn index:')]
    if idx:
        print(f'\nspawn index lines (creation order = desc order is confirmed by "k 0 is the lead"): {len(idx)}')
        for l in idx:
            print('  ' + l)
    return True


def main(argv):
    if len(argv) < 2:
        print(__doc__)
        return 2
    ok = True
    for p in argv[1:]:
        ok = report(p) and ok
    return 0 if ok else 1


if __name__ == '__main__':
    sys.exit(main(sys.argv))
