"""log_report_page.py : the page of tools/log_report.py: its sections, from the build to where the games disagree.

Page (the Markdown being written), each section's sec_* (the build, the clocks, who played, the rounds, lag by round, the
STORE windows, DOWN and revives, the co-op link, the ZFA-44s, the shuttle, the rockets, the Alicorn, the leaderboard,
the errors, UE4SS.log, the checklist, the disagreements), the helpers only they use (perf_windows, store_windows,
fired_in, down_periods, by_shape, collapse, readable) and report(), which puts them in order.

A part of tools/log_report.py (its docstring has the layout): every name log_report defines is here through the import
below, and log_report imports this part back whole, so each name here is log_report.<name> too. Run log_report.py,
never this file; import log_report, not this part.
"""
from log_report import *  # noqa: F401,F403 (log_report's names: it imports this part at its end)


# ---- the page -----------------------------------------------------------------------------------------------------
class Page:
    def __init__(self):
        self.out = []

    def add(self, *lines):
        self.out.extend(lines)

    def h(self, level, text):
        self.out.extend(['', '#' * level + ' ' + text, ''])

    def text(self):
        return '\n'.join(self.out).rstrip() + '\n'


def sec_build(p, games, many):
    p.h(2, 'Build')
    rows = []
    for g in games:
        v = g.version or '?'
        rows.append([md(g.label), md(g.role or '?') + (' (' + md(g.role_why, 100) + ')' if g.role_why else ''),
                     md(v), md(g.runtime or '?'), md((g.hash or '?')[:16]), md(g.b.stamp or g.session.get('start') or '-'),
                     md(g.where, 50)])
    p.add(*table(['Game', 'Role', 'Lua', 'Runtime', 'Build hash', 'Session', 'Bundle'], rows))
    for g in games:
        p.add('', '**%s**: %s, %s lines of Lua log, %s of the runtime\'s, %s crumbs; on %s to %s%s.' % (
            md(g.label), ', '.join('%s %s (%.1f MB)' % (k, md(s.name.rsplit('/', 1)[-1], 60), s.size / 1048576)
                                    for k, s in sorted(g.b.files.items())) or 'no files',
            g.lines['lua'], g.lines['native'], g.lines['crumbs'], g.at(g.first), g.at(g.last),
            '; other sessions in the bundle: ' + md(', '.join(g.b.others[:6]), 200) if g.b.others else ''))
        for note in g.b.notes:
            p.add('', '- ' + md(note))
        if g.ue and g.ue['mods']:
            p.add('', '- UE4SS mods started: ' + md(', '.join(g.ue['mods']), 400))
        if g.ev['loaded'] and len(g.ev['loaded']) > 1:
            p.add('- Lua loaded %d times: %s' % (len(g.ev['loaded']), ', '.join(g.at(t) for t, _ in g.ev['loaded'][:8])))
        cl = getattr(g, 'crumbs_last', None)
        if cl and g.last is not None and cl[-1][0] < g.last - 120:
            p.add('- the crumbs end at %s, %s before the Lua log: their last lines may show a hang or a crash'
                  % (g.at(cl[-1][0]), dur(g.last - cl[-1][0])))
        if cl:
            p.add('- the crumbs\' last line: %s %s' % (g.at(cl[-1][0]), code(cl[-1][1], 200, False)))
        if g.b.crashes:
            p.add('- crash folders in the bundle: ' + md(', '.join(sorted(set(c.name.split('/')[1] if '/' in c.name else c.name
                                                                              for c in g.b.crashes)))[:300], 400))
            for c in g.b.crashes:
                if c.size < 2 << 20 and c.name.lower().endswith(('xml', '.txt', '.log')):
                    m = re.search(r'<ErrorMessage>(.*?)</ErrorMessage>', c.head(1 << 20), re.S)
                    if m:
                        p.add('  - %s: %s' % (md(c.name, 120), code(m.group(1).strip(), 300, False)))
        if g.bundletxt:
            ue = re.search(r'UE4SS\.log: (.*)', g.bundletxt)
            sk = len(re.findall(r'^(?:SKIPPED|PARTIAL) ', g.bundletxt, re.M))
            p.add('- bundle.txt: %d files added, %d skipped or partial%s' % (len(re.findall(r'^added ', g.bundletxt, re.M)), sk,
                                                                            ('; UE4SS.log: ' + md(ue.group(1), 300)) if ue else ''))
        late = [b for b, _, _ in CHECK_GROUPS if vtuple(g.version or '') and vtuple(g.version) < b]
        if late:
            p.add('- this build is older than %s: the checklist\'s %slines can\'t be in its logs' % (
                vtext(late[0]), '' if len(late) == len(CHECK_GROUPS) else ', '.join(vtext(b) for b in late) + ' '))
    rep = [g for g in games if g.report]
    for g in rep:
        p.h(3, 'The player\'s report (%s, report.txt)' % md(g.label))
        for line in g.report.splitlines()[:60]:
            p.add('> ' + md(line, 600) if line.strip() else '>')


def sec_clocks(p, games, ref):
    p.h(2, 'Clocks')
    p.add('Every time on this page is on %s\'s clock. A time in [brackets] is that game\'s own clock (for finding the line '
          'in its log).' % md(ref.label), '')
    rows = []
    for g in games:
        if g is ref:
            rows.append([md(g.label), 'the reference', '-', '-', '%s to %s' % (hms(g.first), hms(g.last))])
            continue
        al = g.aligned
        if al:
            rows.append([md(g.label), signed_hms(((al['offset'] + 43200) % 86400) - 43200), '%d round clears' % al['matched'],
                         '%d s' % al['spread'], '%s to %s' % (g.at(g.first), g.at(g.last))])
        else:
            rows.append([md(g.label), 'not aligned (no round clear in common): its own clock', '0', '-',
                         '%s to %s' % (g.at(g.first), g.at(g.last))])
    p.add(*table(['Game', 'Its clock minus the reference', 'Matched on', 'Spread', 'Its log (reference clock)'], rows))


def sec_players(p, games):
    p.h(2, 'Who played')
    for g in games:
        p.h(3, md(g.label))
        me = 'this game is player %d' % g.slot if g.slot else 'no co-op slot'
        p.add('%s; %s.' % (md(g.role or '?'), me))
        if g.role == 'joiner':
            host = g.names.get(1)
            if host:
                p.add('', 'The host: player 1, %s.' % md(' / '.join(sorted(host))))
        slots = defaultdict(lambda: {'joins': 0, 'left': 0, 'lost': 0, 'up': 0, 'first': None, 'last': None, 'ver': set()})
        def seen(s, t):
            d = slots[s]
            d['first'] = t if d['first'] is None else min(d['first'], t)
            d['last'] = t if d['last'] is None else max(d['last'], t)
        for t, s, what, extra in g.ev['sys']:
            seen(s, t)
            if what in ('joined', 'left', 'lost', 'up'):
                slots[s]['joins' if what == 'joined' else what] += 1
        for t, s, name, ver in g.ev['player_is']:
            seen(s, t)
            slots[s]['ver'].add(ver)
        for t, s, *_ in g.ev['rtt']:
            seen(s, t)
        for t, name, ver, s in g.ev['joined']:
            seen(s, t)
            slots[s]['ver'].add(ver)
        if g.slot:
            seen(g.slot, g.first)
            seen(g.slot, g.last)
        rows = []
        for s in sorted(slots):
            d = slots[s]
            occ = g.occupants.get(s) or [(d['first'], g.name_of(s))]
            who = ', '.join('%s (%s)' % (md(n, 40), g.at(t0)) for t0, n in occ) if len(occ) > 1 else md(occ[0][1], 60)
            rows.append([s, who + (' (this game)' if s == g.slot else ''), g.at(d['first']), g.at(d['last']),
                         d['joins'], d['left'], d['lost'], md(', '.join(sorted(d['ver'])), 60) or '-'])
        if rows:
            p.add('', *table(['Slot', 'Player(s)', 'First seen', 'Last seen', 'Joins', 'Leaves', 'Links lost', 'Survival'], rows))
        ev = []
        said = set()
        for t, who, a, b in sorted(g.ev['refused_join'], key=lambda x: (x[0], -len(x[3]))):
            k = (int(t) // 5, who.upper())
            if k in said:
                continue
            said.add(k)
            ev.append((t, 'refused a join: %s (theirs %s, this game\'s %s)' % (md(who, 60), md(a, 60), md(b, 40))
                       if b else 'refused a join: %s (%s)' % (md(who, 60), md(a, 80))))
        said = set()
        for t, a in g.ev['twohosts']:
            k = int(t) // 5
            if k in said:
                continue
            said.add(k)
            ev.append((t, 'two hosts: ' + md(a, 200)))
            m = re.match(r'(.+) is also the', a)
            other = m.group(1).upper() if m else None
            for s_, occ in (g.occupants.items() if other else ()):
                if any(n.upper() == other for _, n in occ):
                    for lt, ls, w in g.ev['link']:
                        if ls == s_ and t - 600 <= lt <= t and (int(lt), ls) not in said:
                            said.add((int(lt), ls))
                            ev.append((lt, '%s (player %d): link %s' % (md(m.group(1), 60), ls, w)))
                    for t0, n in occ:
                        if n.upper() == other and t < t0 <= t + 300 and (int(t0), s_) not in said:
                            said.add((int(t0), s_))
                            ev.append((t0, '%s back in the room as player %d' % (md(n, 60), s_)))
        for t, text in g.ev['migration']:
            ev.append((t, 'migration: ' + md(text, 200)))
        for t, text in g.ev['leftnote']:
            ev.append((t, 'the host\'s "left" notice: ' + md(text, 200)))
        for t, text in g.ev['runstart']:
            ev.append((t, 'run: ' + md(text, 120)))
        if ev:
            p.add('', 'Hosting, migrations, refusals:', '')
            for t, s in sorted(ev)[:60]:
                p.add('- %s %s' % (g.at(t), s))


def sec_rounds(p, games, ref):
    p.h(2, 'Rounds')
    others = [g for g in games if g is not ref]
    head = ['Run', 'Round', 'Start', 'Clear', 'Length', 'Kind', 'Outcome', 'Players', 'Down (yours)']
    head += ['%s clear' % md(g.label, 30) for g in others]
    rows = []
    for r in ref.rounds:
        row = [r['run'], r['n'], ref.at(r['t']), ref.at(r['clear']), dur(r['clear'] - r['t']) if r['clear'] else '-',
               kind_text(r), md(r['outcome'], 120), r['players'] if r['players'] is not None else '-',
               '%s (%s)' % (r['down'], r['yours']) if r['down'] is not None else '-']
        for g in others:
            c = next((x for x in g.rounds if x['n'] == r['n'] and x['clear'] is not None and
                      r['clear'] is not None and abs(g.ref(x['clear']) - r['clear']) < 600), None)
            row.append(('%+d s' % round(g.ref(c['clear']) - r['clear'])) if c else '-')
        rows.append(row)
    if rows:
        p.add(*table(head, rows))
    else:
        p.add('No round in %s\'s logs.' % md(ref.label))
    for g in others:
        lo = ref.rounds[0]['t'] if ref.rounds else None
        hi = ref.rounds[-1]['end'] if ref.rounds else None
        extra = [r for r in g.rounds if lo is None or not (lo - 60 <= g.ref(r['t']) <= hi + 60)]
        if extra:
            p.add('', 'Rounds only %s\'s logs have:' % md(g.label), '')
            p.add(*table(['Run', 'Round', 'Start', 'Clear', 'Kind', 'Outcome'],
                         [[r['run'], r['n'], g.at(r['t']), g.at(r['clear']), kind_text(r), md(r['outcome'], 100)] for r in extra]))
    kinds = Counter((r['kind'] if r['kind'] != 'special' else 'special') for r in ref.rounds)
    if kinds:
        p.add('', 'Kinds: ' + ', '.join('%s %d' % (k, v) for k, v in kinds.most_common()) + '.')


def perf_windows(perf):
    """each perf line's window: back to the line before when its ticks (250 ms each) about fill the gap, else its ticks
    back from it (a pause, a load, a new run between)"""
    prev = None
    for x in perf:
        span = x['ticks'] * 0.25
        x['lo'] = prev if prev is not None and x['t'] - prev <= span * 1.6 else x['t'] - span
        prev = x['t']


def overlap(a0, a1, b0, b1):
    return max(0.0, min(a1, b1) - max(a0, b0))


def wmean(pairs):
    w = sum(o for _, o in pairs)
    return sum(v * o for v, o in pairs) / w if w else None


def sec_lag(p, games):
    p.h(2, 'Lag by round')
    p.add('The Lua tick runs on the game thread, so its cost is frame time. A `perf:` line comes every ~5 minutes and covers '
          'the ticks before it: its numbers go to the rounds its window overlaps, weighted by the overlap (pieces under 5 s '
          'left out); "share" is how much of each line\'s window was in the round (the heaviest line and the worst half only '
          'from lines mostly in it). The runtime\'s `frames:` / `units:` lines (0.74.52) cover the minute before them.')
    for g in games:
        p.h(3, md(g.label))
        perf = g.ev['perf']
        if not perf and not g.ev['frames'] and not g.ev['units']:
            p.add('No perf, frames or units lines.')
            continue
        perf_windows(perf)
        rows, by = [], defaultdict(list)
        for x in perf:
            got = 0.0
            for r in g.rounds:
                o = overlap(x['lo'], x['t'], r['t'], r['end'])
                got += o
                if o >= 5:
                    by[r['kind']].append((x, o))
            if x['t'] - x['lo'] - got >= 5:
                by['outside the rounds'].append((x, x['t'] - x['lo'] - got))
        for r in g.rounds:
            lo, hi = r['t'], r['end']
            ps = [(x, overlap(x['lo'], x['t'], lo, hi)) for x in perf]
            ps = [(x, o, o / max(1.0, x['t'] - x['lo'])) for x, o in ps if o >= 5]
            fr = [x for x in g.ev['frames'] if lo <= x[0] - 30 < hi]
            un = [x for x in g.ev['units'] if lo <= x[0] - 30 < hi]
            if not (ps or fr or un):
                continue
            main = max(ps, key=lambda e: e[1])[0] if ps else None
            ua = [(x['ua'], o) for x, o, _ in ps if 'ua' in x]
            whole = [x for x, _, sh in ps if sh >= 0.5]
            rows.append([r['n'], kind_text(r), ('%.1f' % wmean([(x['avg'], o) for x, o, _ in ps])) if ps else '-',
                         ('%.1f' % max(x['avg'] for x in whole)) if whole else '-',
                         ('%d (%s)' % (len(ps), ', '.join('%d%%' % round(100 * sh) for _, _, sh in ps))) if ps else '-',
                         ('%.0f' % max(x['worst'] for x in whole)) if whole else '-',
                         md(', '.join('%s %.1f' % (a, b) for a, b, _ in main['parts']), 80) if main else '-',
                         ('%.1f / %.2f ms' % (wmean([(u[0], o) for u, o in ua]), wmean([(u[1], o) for u, o in ua]))) if ua else '-',
                         ('%d-%d' % (min(x[1] for x in fr), max(x[1] for x in fr))) if fr else '-',
                         ('%d' % max(x[4] for x in fr)) if fr else '-', ('%d' % sum(x[6] for x in fr)) if fr else '-',
                         ('%d / %d us' % (max(x[2] for x in un), max(x[3] for x in un))) if un else '-'])
        if rows:
            p.add(*table(['Round', 'Kind', 'Tick avg ms', 'Heaviest line ms', 'Perf lines (share)', 'Worst half ms',
                          'Top parts (ms a tick)', 'SV_UnitAlive a tick / ms', 'fps', 'Worst frame ms', 'Frames >100 ms',
                          'units: avg / worst'], rows))
        if by:
            p.add('', 'Tick avg by round kind: ' + ', '.join('%s %.1f ms (%d line%s, %s)' % (
                k, wmean([(x['avg'], o) for x, o in v]), len(v), '' if len(v) == 1 else 's', dur(sum(o for _, o in v)))
                for k, v in sorted(by.items())) + '.')
        if perf:
            hi = max(perf, key=lambda x: x['avg'])
            p.add('', 'Heaviest perf line: %s, tick avg %.1f ms, worst half %.0f ms%s; memory %s MB at the first.' % (
                g.at(hi['t']), hi['avg'], hi['worst'],
                ', SV_UnitAlive %.1f a tick %.2f ms' % hi['ua'][:2] if 'ua' in hi else '', perf[0]['mem'] or '?'))


def store_windows(g):
    wins = []
    open_t = None
    for t, what in g.ev['store']:
        if what == 'held' and open_t is None:
            open_t = t
        elif what == 'running' and open_t is not None:
            wins.append([open_t, t, 'music hold'])
            open_t = None
    if open_t is not None:
        wins.append([open_t, None, 'music hold'])
    merged = []
    for w in wins:
        if merged and merged[-1][1] is not None and w[0] - merged[-1][1] <= 5:
            merged[-1][1] = w[1]
        else:
            merged.append(w)
    wins = merged
    if not wins:
        st = None
        for t, ty, what in g.ev['minigame']:
            if what in ('starts', 'deactivated') and st is None:
                st = t
            elif what == 'ends' and st is not None:
                wins.append([st, t, 'minigame'])
                st = None
    return wins


def fired_in(g, lo, hi):
    """the RE_SV_* events g's logs say ran in [lo, hi] (its own clock), and those they say did NOT (~)"""
    c = Counter()
    for t, names, theirs, nope in g.ev['resv']:
        if lo <= t <= hi:
            for nm in set(names):
                c[nm + (' (h)' if theirs else '')] += 1
            if nope:
                c['~%s%s (%s)' % (nope[0], ' (h)' if theirs else '', nope[1])] += 1
    for t, nm, res in g.ev['crumb_ev']:
        if lo <= t <= hi and nm not in c and nm + ' (h)' not in c:
            c[nm if res == 1 else '~%s (not fired: %d)' % (nm, res)] += 1
    return c


# ---- STOREQ (0.74.66, Scripts/sv_rounds_store.lua): what a game's gate held, and what came of it once it opened -------
SQ_PRE, SQ_AFTER = 120, 5           # (the gate shuts on the airfield before the STORE, and stays shut 3 s after it)
SQ_WHY = [('STORE is open', 'STORE open'), ('not open yet', 'on the airfield, before the STORE'), ('a moment ago', 'just after')]


def sq_why(why):
    return next((short for k, short in SQ_WHY if k in why), why)


SQ_START = [    # (a line that starts a window's queue: held, to be fired again, not fired late, a bomber flight watched)
    (R(r"storeq: the host's (\S+) held here: (.*?); fired here once it's shut"), lambda m: '%s (h) held (%s)' % (m.group(1), sq_why(m.group(2)))),
    (R(r"storeq: (\S+) fired while (.*?): fired again here once it's shut"), lambda m: '%s to fire again (%s)' % (m.group(1), sq_why(m.group(2)))),
    (R(r"storeq: the host's (\S+) not fired here: (.*?), and it changes nothing that lasts"),
     lambda m: '~%s (h) not fired late (%s: nothing that lasts)' % (m.group(1), sq_why(m.group(2)))),
    (R(r'storeq: bomber flight (\S+) appeared while (.*?): its orders read back'),
     lambda m: 'bomber flight %s appeared (%s): its orders read back' % (m.group(1), sq_why(m.group(2)))),
]
SQ_BEHIND = R(r"storeq: the host's (\S+) goes behind what's held here: (.*?) \(\w+: the first")
SQ_OPEN = R(r"storeq: (?:this game's events can take again: (\d+) to fire here in order|(\d+) more to fire here in order, "
            r"behind what fired just before them) \((.*)\)$")
SQ_DONE = R(r'storeq: done here: (.*)$')
SQ_ERR = R(r'storeq: (?:gate |bombers )?error ')
SQ_TAIL = R(r' \(\w+: the first (?:held )?this time\)$')
SQ_TROUBLE = R(r"never took here|never had its orders|\(not fired: |STORE still open \(as before\)|its orders not "
               r"(?:given again|checked)|whether they took isn't readable|^storeq: (?:gate |bombers )?error ")


def storeq_windows(g, wins):
    """STOREQ's lines by STORE window: {i: {held, open, after, done}}, i 0 for none. A line that starts a queue (held,
    to be fired again, a bomber flight watched) goes to the window it's in, or the one it comes up to SQ_PRE s before;
    the rest (as the gate opened, each one's outcome, the summary) to the window of the queue before them; an error to
    the window it's in"""
    def by_time(t, before):
        for i, (o, s, _) in enumerate(wins, 1):
            if o - before <= t <= (s if s is not None else (g.last or o)) + SQ_AFTER:
                return i
        return 0
    out = defaultdict(lambda: {'held': [], 'open': [], 'after': [], 'done': []})
    cur = None
    for t, text in g.ev['storeq']:
        start = next((f(m) for rx, f in SQ_START for m in [rx.match(text)] if m), None)
        if start is not None:
            cur = by_time(t, SQ_PRE)
            out[cur]['held'].append((t, start))
            continue
        if SQ_ERR.match(text):
            out[by_time(t, 0)]['after'].append((t, text))
            continue
        d = out[cur if cur is not None else by_time(t, 0)]
        m, mo, md_ = SQ_BEHIND.match(text), SQ_OPEN.match(text), SQ_DONE.match(text)
        if m:
            d['held'].append((t, '%s (h) behind what\'s held (%s)' % (m.group(1), m.group(2))))
        elif mo:
            d['open'].append((t, mo.group(1) or mo.group(2), bool(mo.group(2)), mo.group(3)))
        elif md_:
            d['done'].append((t, md_.group(1)))
        else:
            d['after'].append((t, text))
    return out


def sq_list(items, n, at=None):
    """(t, text)s as one cell: a STOREQ line without its prefix and its kind's tail, trouble bold, n at most"""
    parts = []
    for t, x in items[:n]:
        s = md(SQ_TAIL.sub('', x[8:] if x.startswith('storeq: ') else x), 160)
        s = ('%s ' % at(t) if at else '') + s
        parts.append('**%s**' % s if SQ_TROUBLE.search(x) else s)
    if len(items) > n:
        parts.append('+%d more' % (len(items) - n))
    return '; '.join(parts) or '-'


def sec_storeq(p, g, wins):
    q = storeq_windows(g, wins)
    if not q:
        return
    p.add('', 'STOREQ by window (- none of them):', '')
    rows = []
    for i in sorted(q, key=lambda k: (k == 0, k)):
        d = q[i]
        opened = '; '.join('%s %s %s (%s)' % (g.at(t), n, 'more, behind' if more else 'to fire', md(k, 160))
                           for t, n, more, k in d['open'][:6]) or '-'
        done = '; '.join(('**%s %s**' if re.search(r'\b(?:failed|refused|late) \d', x) else '%s %s') % (g.at(t), md(x, 300))
                         for t, x in d['done'][:6]) or '-'
        rows.append([i or '-', sq_list(d['held'], 14), opened, sq_list(d['after'], 16, g.at), done])
    p.add(*table(['#', 'Held or to fire again (the first of a kind)', 'As the gate opened', 'Then (the first of a kind)',
                  'Done'], rows))


def sec_store(p, games, ref):
    p.h(2, 'STORE windows')
    p.add('A window is the music\'s hold (`music: track clock held (landing store)` to `running`; else the runtime\'s '
          '`minigame:` lines). Hard rule 64: a host event fired in it runs none of its records. **Bold**: fired and not '
          'one of the repeating orders, so check it took; (h): the host\'s, forwarded to this game; ~: named as NOT run '
          'here (not fired, dropped, held, didn\'t take); !: a special\'s moment logged inside the window (a liftoff, a '
          'launch: did it take?). Each other game\'s windows also list what the reference\'s log (the host\'s) fired in '
          'them, its clock aligned. From 0.74.66 STOREQ\'s table under each game\'s (Scripts/sv_rounds_store.lua): what its '
          'gate held, or saw fired while it was shut, and what came of it once it opened, by window; the log names the '
          'first of each kind a spell, so the counts are the gate\'s as it opened and the summary the queue\'s at its end. '
          '**Bold** there: never took, refused, fired late into a STORE, a flight left without its orders, an error.')
    bold = lambda k: k.startswith('!') or (not k.startswith('~') and not REPEATING.search(k))
    for g in games:
        p.h(3, md(g.label))
        wins = store_windows(g)
        if not wins:
            p.add('No STORE window.')
            sec_storeq(p, g, wins)
            continue
        rows = []
        n_ev = 0
        theirs = g is not ref and g.aligned and ref.first is not None
        for i, (o, s, how) in enumerate(wins, 1):
            hi = s if s is not None else (g.last or o)
            c = fired_in(g, o, hi)
            mg = [x for x in g.ev['minigame'] if o - 3 <= x[0] <= hi + 3]
            moments = [x for t, x in g.ev['shuttle'] + g.ev['rocket'] if o <= t <= hi and
                       re.search(r'lifted off|countdown (?:over|running)|launched \(|escaped \(|liftoff', x)]
            if moments:
                c.update('!' + re.sub(r'^(special|coop|callout): ', '', m)[:70] for m in moments)
            r, _ = round_at(g, o)
            n_ev += sum(c.values())
            rows.append([i, g.at(o), g.at(s), dur(hi - o), r['n'] if r else 'between',
                         ' '.join('%d %s' % (ty, w) for _, ty, w in mg[:4]) or '-', counts_text(c, 14, bold)]
                        + ([counts_text(fired_in(ref, g.ref(o), g.ref(hi)), 14, bold)] if theirs else []))
        p.add(*table(['#', 'Opened', 'Shut', 'Length', 'Round', 'Minigames (runtime)', 'Inside: RE_SV_* events, ! moments']
                     + (['%s\'s log in the window' % md(ref.label, 40)] if theirs else []), rows))
        p.add('', '%d windows, %s in all; %d event mentions inside.' % (len(wins), dur(sum(((s or g.last) - o) for o, s, _ in wins)), n_ev))
        sec_storeq(p, g, wins)


def down_periods(g):
    """each player's DOWN periods on this game: [{who, slot, t, back, by, end, how}]"""
    me = g.steam or 'this game'
    up = {}                                     # (names as the callouts give them: callout_name)
    for s_, ns in g.names.items():
        for n in ns:
            up[callout_name(n)] = s_
    leaves = defaultdict(list)                  # NAME -> times it left (the callout) or its slot's sys|left
    for t, name, what in g.ev['calljoin']:
        if what == 'left':
            leaves[callout_name(name)].append(t)
    for t, s_, w, x in g.ev['sys']:
        if w == 'left':
            for n in g.names.get(s_, ()):
                leaves[callout_name(n)].append(t)
    periods, open_by = [], {}
    evs = sorted([(t, 0, w, n, x) for t, w, n, x in g.ev['down']] + [(t, 1, w, n, x) for t, w, n, x in g.ev['back']],
                 key=lambda e: (e[0], e[1]))
    for t, kind, who, name, extra in evs:
        key = 'SELF' if who == 'self' else callout_name(name or '?')
        if kind == 0:
            if key in open_by and t - open_by[key]['t'] < 30:
                continue
            if key in open_by:
                periods.append(open_by.pop(key))
            open_by[key] = {'who': me if key == 'SELF' else name, 'key': key, 't': t, 'back': None, 'by': None,
                            'slot': g.slot if key == 'SELF' else up.get(key)}
        else:
            d = open_by.pop(key, None)
            if d:
                d['back'], d['by'] = t, extra
                periods.append(d)
    periods.extend(open_by.values())
    for d in periods:
        if d['back'] is None:
            lv = next((x for x in sorted(leaves.get(d['key'], ())) if x >= d['t']), None)
            ro = next((ot for ot, _ in sorted(g.ev['runover']) if ot >= d['t']), None)
            if lv is not None and (ro is None or lv < ro):
                d['end'], d['how'] = lv, 'left the mission'
            elif ro is not None:
                d['end'], d['how'] = ro, 'run over'
            else:
                d['end'], d['how'] = g.last, 'still down at the log\'s end'
    return sorted(periods, key=lambda x: x['t'])


def sec_down(p, games):
    p.h(2, 'DOWN and revives')
    for g in games:
        p.h(3, md(g.label))
        revs = g.ev['revive']
        rows = []
        for d in down_periods(g):
            price = '-'
            if d['back'] is not None:
                near = [x for x in revs if abs(x[0] - d['back']) <= 15 and (d['slot'] is None or x[2] == d['slot'])]
                if near:
                    rv = min(near, key=lambda x: abs(x[0] - d['back']))
                    price = '%d (by player %d; the run\'s revive %d%s; round %d\'s price)' % (
                        rv[3], rv[1], rv[4], ', their %s' % rv[5] if rv[5] else '', rv[6])
            back = g.at(d['back']) if d['back'] is not None else '%s %s' % (d['how'], g.at(d['end']))
            rows.append([md(d['who'], 40), g.at(d['t']), back, dur((d['back'] or d['end'] or d['t']) - d['t']),
                         md(d['by'] or '-', 40), price])
        if rows:
            p.add(*table(['Player', 'Down', 'Back', 'Down for', 'Revived by', 'Price'], rows))
        else:
            p.add('Nobody down.')
        if revs:
            p.add('', 'Revives priced by this game: %d, %d zollars in all.' % (len(revs), sum(x[3] for x in revs)))
        notes = g.ev['revive_note'] + [(t, 'STORE: ' + x) for t, x in g.ev['revive_shop']] + g.ev['down_note']
        if notes:
            p.add('', 'Revive answers and notes (refusals among them):', '')
            by_shape(p, g, notes, 20)


def by_shape(p, g, notes, n):
    """(t, line)s grouped by their shape: each shape's count and its first line"""
    c, firsts = Counter(shape_of(x) for _, x in notes), {}
    for t, x in sorted(notes):
        firsts.setdefault(shape_of(x), (t, x))
    for k, v in c.most_common(n):
        p.add('- %dx, first %s: %s' % (v, g.at(firsts[k][0]), md(firsts[k][1], 200)))


def sec_link(p, games):
    p.h(2, 'Co-op link')
    for g in games:
        if not (g.ev['rtt'] or g.ev['link'] or g.ev['sys']):
            continue
        p.h(3, md(g.label))
        per = defaultdict(lambda: {'rtt': [], 'resent': 0, 'last': None, 'lost_min': 0, 'names': set()})
        for t, s, name, state, rtt, resent in g.ev['rtt']:
            d = per[s]
            d['names'].add(name)
            if state == 'linked' and rtt > 0:
                d['rtt'].append(rtt)
            else:
                d['lost_min'] += 1
            if d['last'] is not None and resent >= d['last']:
                d['resent'] += resent - d['last']
            elif d['last'] is None or resent < d['last']:
                d['resent'] += resent
            d['last'] = resent
        lk = defaultdict(Counter)
        for t, s, w in g.ev['link']:
            lk[s][w] += 1
        for t, s, w, extra in g.ev['sys']:
            if w in ('lost', 'up', 'left', 'joined'):
                lk[s]['sys ' + w] += 1
        rows = []
        for s in sorted(set(per) | set(lk)):
            d = per[s]
            r = sorted(d['rtt'])
            rows.append([s, md(' / '.join(sorted(d['names'])) or g.name_of(s), 80),
                         ('%d / %d / %d' % (r[0], r[len(r) // 2], r[-1])) if r else '-', d['resent'], d['lost_min'],
                         lk[s]['lost'] or lk[s]['sys lost'], lk[s]['up'] or lk[s]['sys up'], lk[s]['gone'] or lk[s]['sys left']])
        p.add(*table(['Slot', 'Player', 'rtt min / median / max ms', 'Resent', 'Minutes "link lost"', 'Links lost', 'Links back',
                      'Gone / left'], rows))
        st = g.ev['streams']
        if st:
            p.add('', 'Enemy streams (this game\'s minute lines): %d failed moves, up to %d bad packets, lateness up to %d ms.'
                  % (sum(x[2] for x in st), max(x[3] for x in st), max(x[4] for x in st)))
        by_shape(p, g, g.ev['link_note'], 10)
        for t, text in g.ev['leftnote']:
            p.add('- %s the host\'s "left" notice: %s' % (g.at(t), md(text, 200)))
        if g.ev['link']:
            ev = [(t, 'player %d (%s): link %s' % (s, md(g.name_of(s, t), 60), w)) for t, s, w in g.ev['link']]
            ev += [(t, 'player %d: sys|%s %s' % (s, w, md(x, 60))) for t, s, w, x in g.ev['sys'] if w in ('joined', 'left', 'samerole')]
        else:
            ev = [(t, 'player %d (%s): sys|%s %s' % (s, md(g.name_of(s, t), 60), w, md(x, 60))) for t, s, w, x in g.ev['sys']]
        ev.sort()
        if ev:
            p.add('', '<details><summary>Link events (%d)</summary>' % len(ev), '')
            for t, s in ev[:400]:
                p.add('- %s %s' % (g.at(t), s))
            p.add('', '</details>')


def sec_zfa(p, games):
    p.h(2, 'ZFA-44s')
    for g in games:
        e = g.ev
        if not (e['census'] or e['launched'] or e['blast'] or e['carrier'] or e['finished'] or e['stillup']):
            continue
        p.h(3, md(g.label))
        on = [x for x in e['carrier'] if 'on station' in x[1]]
        p.add('- carriers on station: %d; launches: %d (%d planes seen launched)' % (
            len(on), len([x for x in e['carrier'] if 'launches its ZFA-44s' in x[1]]), sum(x[1] for x in e['launched'])))
        fin = sum(x[1] for x in e['finished'])
        p.add('- finished off by the carriers\' ends: %d%s; one-plane finishes logged: %d; "could not be finished": %d'
              % (fin, (', %d of them could not be' % sum(x[2] for x in e['finished'])) if any(x[2] for x in e['finished']) else '',
                 len(e['finished_one']), len(e['notfinished'])))
        if e['stillup']:
            p.add('- "still has N up after 30 s" (finished off, yet up): %d times, %d planes in all, first %s'
                  % (len(e['stillup']), sum(x[3] for x in e['stillup']), g.at(e['stillup'][0][0])))
        if e['blast']:
            xs = [x[1] for x in e['blast']]
            ys = [x[2] for x in e['blast']]
            p.add('- Helios blasts: %d, %d enemy aircraft down by them; ZFA-44 down after its blast: %d, NOT down: %d; at x %.1f to %.1f km, y %.1f to %.1f km'
                  % (len(e['blast']), sum(x[3] for x in e['blast']), sum(1 for x in e['blast'] if x[4] == 'down'),
                     sum(1 for x in e['blast'] if x[4] == 'NOT down'), min(xs), max(xs), min(ys), max(ys)))
        pos = [(float(a), float(b)) for x in e['launched'] for a, b in x[2]] + [(x[1], x[2]) for x in e['zpos']]
        if e['zpos']:
            xs = [x[1] for x in e['zpos']]
            ys = [x[2] for x in e['zpos']]
            p.add('- the 30 s position lines: %d, x %.1f to %.1f km, y %.1f to %.1f km' % (len(xs), min(xs), max(xs), min(ys), max(ys)))
        elif pos:
            p.add('- launch positions: x %.1f to %.1f km, y %.1f to %.1f km' % (min(a for a, _ in pos), max(a for a, _ in pos),
                                                                              min(b for _, b in pos), max(b for _, b in pos)))
        if e['census']:
            by = defaultdict(set)
            for t, rnd, obj, unit in e['census']:
                by[rnd].add(obj)
            rounds = sorted(by)
            allobj = set().union(*by.values())
            first, last = rounds[0], rounds[-1]
            seen_at = {}
            for r in rounds:
                for o in by[r]:
                    seen_at.setdefault(o, r)
            since = max(seen_at[o] for o in by[last])
            p.add('- the allies\' census (`allies: ... at round N\'s level`): ZFA-44 objects named at %d rounds (%d-%d), %d '
                  'different ones in all; round %d\'s %d were every one of them named already at round %d%s'
                  % (len(rounds), first, last, len(allobj), last, len(by[last]), since,
                     (' (the same objects for %d rounds: none of them died)' % (last - since)) if last - since >= 3 else ''))
            p.add('- per census round: ' + ', '.join('%d: %d' % (r, len(by[r])) for r in rounds[:60]))
        for t, text in (e['notfinished'] + e['finished_one'])[:8]:
            p.add('- %s %s' % (g.at(t), code(text, 200, False)))


def collapse(items, gap=600):
    """[(t, n, (text, last t))]: lines of one shape in a row (within gap s) as one"""
    out = []
    for t, text in sorted(items, key=lambda x: x[0]):
        k = shape_of(re.sub(r'\d+%', 'N%', text))
        if out and out[-1][3] == k and t - out[-1][4] <= gap:
            out[-1][1] += 1
            out[-1][4] = t
            continue
        out.append([t, 1, text, k, t])
    return [(t, n, (text, last)) if n > 1 else (t, n, (text, t)) for t, n, text, k, last in out]


def sec_lines(p, games, key, title, intro, limit=80):
    shown = [g for g in games if g.ev[key]]
    p.h(2, title)
    if intro:
        p.add(intro)
    if not shown:
        p.add('', 'Nothing in these logs.')
        return
    for g in shown:
        p.h(3, md(g.label))
        rows = collapse(g.ev[key])
        for t, n, text in rows[:limit]:
            p.add('- %s%s %s' % (g.at(t), ' (x%d to %s)' % (n, g.at(text[1])) if n > 1 else '', code(text[0], 240, False)))
        if len(rows) > limit:
            p.add('- ... %d more' % (len(rows) - limit))


def sec_shuttle(p, games):
    p.h(2, 'The shuttle')
    p.add('`lifted off (event package ...)`: its records ran; `(countdown over ...)`: the clock ran out first (Saint Alessia\'s '
          'run of 0.74.36: the liftoff lost in her STORE). 0.74.51+ replays it: `lifted off here at the replay\'s try N`.')
    any_ = False
    for g in games:
        lines = [(t, x) for t, x in g.ev['shuttle'] if not ('row OP' in x or x.startswith('specials:'))]
        if not lines:
            continue
        any_ = True
        p.h(3, md(g.label))
        for t, x in lines:
            m = re.search(r"lifted off \(([^;)]*)|lifted off here at (the replay's try \d+)", x)
            if m and not x.startswith('callout'):
                p.add('- **%s lifted off: %s**' % (g.at(t), md(m.group(1) or m.group(2), 80)))
        flags = [(t, f.get('SV_ShuttleLaunched'), f.get('SV_ShuttleRound')) for t, f in g.ev['probe'] if 'SV_ShuttleLaunched' in f]
        ch = []
        prev = None
        for t, a, b in flags:
            if (a, b) != prev:
                ch.append('%s SV_ShuttleLaunched=%s SV_ShuttleRound=%s' % (g.at(t), a, b))
                prev = (a, b)
        if len(ch) > 1:
            p.add('- the flags as the round probes read them: ' + '; '.join(ch[:12]))
        for t, n, x in collapse(lines)[:40]:
            p.add('- %s%s %s' % (g.at(t), ' (x%d to %s)' % (n, g.at(x[1])) if n > 1 else '', code(x[0], 240, False)))
    if not any_:
        p.add('', 'No shuttle round in these logs.')


def sec_alicorn(p, games):
    p.h(2, 'The Alicorn')
    any_ = False
    for g in games:
        e = g.ev
        if not (e['alicorn'] or e['tank'] or e['corehit']):
            continue
        any_ = True
        p.h(3, md(g.label))
        if e['tank']:
            by = defaultdict(lambda: [0, 0])
            for t, k, d, left in e['tank']:
                by[k][0] += 1
                by[k][1] += d
            p.add('- tank hits: ' + ', '.join('%s %d (%d health)' % (k, v[0], v[1]) for k, v in sorted(by.items())))
        if e['corehit']:
            p.add('- core hits: %d, %d health in all, the last %s (%s left%s)' % (
                len(e['corehit']), sum(x[1] for x in e['corehit']), g.at(e['corehit'][-1][0]), e['corehit'][-1][2],
                ', %s%%' % e['corehit'][-1][3] if e['corehit'][-1][3] else ''))
        else:
            p.add('- core hits logged: none (`special: Alicorn core hit:` is 0.74.52\'s)')
        keep = [x for x in e['alicorn'] if re.search(r"core|Core|CORE|sunk|dives|surfaces|up$|SV_Unit_Alicorn|joiners' hits|"
                                                       r"ballast tanks|hull at|copy here|brought up to date|sized|bound", x[1])]
        for t, x in keep[:50]:
            p.add('- %s %s' % (g.at(t), code(x, 240, False)))
    if not any_:
        p.add('', 'No Alicorn round in these logs.')


def sec_board(p, games):
    p.h(2, 'Leaderboard')
    for g in games:
        p.h(3, md(g.label))
        ans = Counter(k for _, k, _ in g.ev['lb_answer'])
        sends = sum(1 for _, w, x in g.ev['lb'] if w == 'lua' and re.match(r'(sending|resending)', x))
        p.add('Run id %s; sends %d; answers: %s.' % (md(g.run_id or '-'), sends,
                                                     ', '.join('%s %d' % (md(k), v) for k, v in ans.items()) or 'none'))
        for t, w, x in sorted(g.ev['lb'], key=lambda e: e[0])[:40]:
            p.add('- %s %s%s' % (g.at(t), '(runtime) ' if w == 'native' else '', code(x, 300, False)))


def sec_issues(p, games, many):
    p.h(2, 'Errors and refusals')
    p.add('Lines with error / FAILED / refused / NOT / not fired / could not / given up ... (counts like "0 failed" and '
          'callouts left out), grouped by their shape (numbers as N).')
    rows = []
    for g in games:
        for (where, shape), (n, t0, t1, ex) in g.issues.items():
            rows.append((n, g, where, t0, t1, ex))
    rows.sort(key=lambda x: (-x[0], x[3]))
    if not rows:
        p.add('', 'None.')
        return
    head = (['Game'] if many else []) + ['Count', 'Log', 'First', 'Last', 'First line']
    p.add('', *table(head, [([md(g.label, 30)] if many else []) + [n, where, g.at(t0), g.at(t1), code(ex, 200)]
                           for n, g, where, t0, t1, ex in rows[:60]]))
    if len(rows) > 60:
        p.add('', '%d more shapes, %d lines.' % (len(rows) - 60, sum(r[0] for r in rows[60:])))
    for g in games:
        if g.game_errs:
            p.add('', '%s: the game\'s own logs (Saved/Logs):' % md(g.label), '')
            for (name, shape), n in g.game_errs.most_common(12):
                p.add('- %dx %s: %s' % (n, md(name.rsplit('/', 1)[-1], 60), code(shape, 200, False)))


def sec_ue4ss(p, games):
    shown = [g for g in games if g.ue]
    if not shown:
        return
    p.h(2, 'UE4SS.log')
    for g in shown:
        u = g.ue
        p.h(3, md(g.label))
        p.add('%s: %d lines, %.1f MB, %s to %s%s%s.' % (md(u['name'].rsplit('/', 1)[-1], 60), u['lines'], u['bytes'] / 1048576,
                                                    md(u['first'] or '?'), md(u['last'] or '?'),
                                                    '; started over %d times' % u['started_over'] if u['started_over'] else '',
                                                    '; the copy stopped at its cap' if u['cap'] else ''))
        if u['srcs']:
            tot = max(1, u['lines'])
            p.add('', 'Lines by source: ' + ', '.join('%s %d (%.1f%%)' % (md(s, 40), c, 100.0 * c / tot) for s, c in u['srcs']) + '.')
        p.add('', *table(['Count', 'Share', 'Most repeated line shapes'],
                         [[c, '%.1f%%' % (100.0 * c / max(1, u['lines'])), code(s, 200)] for s, c in u['top']]))
        if u['errs']:
            p.add('', 'Error-looking lines (first of each shape):', '')
            p.add(*table(['Count', 'First', 'Line'], [[c, md(st or '-', 30), code(x, 200)] for c, st, x in u['errs']]))
        if g.stats_txt:
            p.add('', 'UE4SS_stats: ' + md(' '.join(l for l in g.stats_txt.splitlines() if l.startswith('ue4ss_') and
                                                     'top_line' not in l), 400))


def readable(rx):
    """a checklist regex as a reader sees the line: N a number, X a word, ... anything"""
    s = rx.replace(r'\d+', 'N').replace(r'\S+', 'X').replace(r'\w+', 'X').replace('.*', '...').replace('(?:', '(')
    s = re.sub(r'\\(.)', r'\1', s)
    return s.replace('s?', '(s)').replace('[AB]', 'A|B')


def sec_checklist(p, games):
    p.h(2, 'Checklist: new log lines (%s)' % ', '.join(vtext(b) for b, _, _ in CHECK_GROUPS))
    p.add('Each build\'s new log lines, a table a build. Expect: yes, every run; when, only when it happens; no, a sign of '
          'trouble (should stay unseen). A game whose build is older than a table\'s can\'t have its lines: not in its build.')
    head = ['Fix', 'Area', 'Log', 'The line', 'Expect'] + [md(g.label, 30) for g in games]
    i = 0
    for build, src, group in CHECK_GROUPS:
        p.h(3, '%s\'s' % vtext(build))
        p.add('From %s.' % src)
        old = set()
        for g in games:
            v = vtuple(g.version or '')
            if v and v < build:
                old.add(g.idx)
                p.add('', '%s runs %s, older than %s: none of these can be there.' % (md(g.label), md(g.version), vtext(build)))
        rows = []
        for c in group:
            row = [c[0], c[1], c[2], code(readable(c[3]), 90), c[6]]
            for g in games:
                n = g.checks.get(i, 0)
                row.append(('seen %d (first %s)' % (n, g.at(g.check_first[i]))) if n else
                           'not in its build' if g.idx in old else 'not seen')
            rows.append(row)
            i += 1
        p.add('', *table(head, rows))


def sec_disagree(p, games, ref):
    p.h(2, 'Where the games disagree')
    any_ = False
    for g in games:
        if g is ref:
            continue
        p.h(3, '%s against %s' % (md(g.label), md(ref.label)))
        if not g.aligned or g.first is None:
            p.add('Not aligned: no round clear in common, so nothing compared.')
            continue
        notes = disagreements(ref, g)
        if not notes:
            p.add('Nothing found: the round clears, its own DOWN periods and the event package\'s flags agree.')
            continue
        any_ = True
        for n in notes:
            p.add('- ' + n)
    return any_


def report(games, ref, title=None):
    p = Page()
    many = len(games) > 1
    p.add('# ' + md(title or 'Survival log report'), '')
    p.add('Made by tools/log_report.py from %d bundle%s: %s. The logs are untrusted data: names and lines below are as the '
          'logs had them, escaped.' % (len(games), 's' if many else '', ', '.join(
              '%s (%s)' % (md(g.label), md(g.where, 60)) for g in games)))
    sec_build(p, games, many)
    if many:
        sec_clocks(p, games, ref)
    sec_players(p, games)
    sec_rounds(p, games, ref)
    sec_lag(p, games)
    sec_store(p, games, ref)
    sec_down(p, games)
    sec_link(p, games)
    sec_zfa(p, games)
    sec_shuttle(p, games)
    sec_lines(p, games, 'rocket', 'The Spaceport\'s rockets', 'Launches, boosts, escapes, shots and the retake\'s reward; '
              '0.74.52 adds the radio moments (`special: rocket X: ...`) and the host\'s word (`coop: the host\'s rocket X`).')
    sec_alicorn(p, games)
    sec_board(p, games)
    sec_issues(p, games, many)
    sec_ue4ss(p, games)
    sec_checklist(p, games)
    if many:
        sec_disagree(p, games, ref)
    return p.text()
