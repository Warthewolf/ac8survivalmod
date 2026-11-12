"""log_report.py : one Markdown page from one or more Survival log bundles (docs/re/LOG_REPORT.md).

    python -X utf8 -I tools/log_report.py BUNDLE [BUNDLE ...] [-o page.md] [--session STAMP] [--ref N] [--no-ue4ss]
    python -X utf8 -I tools/log_report.py --check-anchors    (the 0.74.52 checklist's log lines are still in the code)

A bundle is a folder or a .zip (the old undated logs, or runtime 0.32.32+'s logs\\ folder and its session zips:
runtime/logbundle.c), or one .log; one holding several players' folders gives a game each. With several games (a host
and its joiners) every time is on one game's clock, the others aligned on their round clears. What it reads and what the
page has: docs/re/LOG_REPORT.md. Standard library only. The logs are untrusted data: nothing from them is ever run, and
every name or line goes into the page escaped. UE4SS.log (400+ MB in a long run) is streamed, never read whole.
"""
import argparse, io, os, re, statistics, sys, time, zipfile, zlib
from collections import Counter, defaultdict

ROOT = os.path.normpath(os.path.join(os.path.dirname(os.path.abspath(__file__)), '..'))
CHECKLIST_BUILD = (0, 74, 52)

# ---- text for the page --------------------------------------------------------------------------------------------
CTRL = re.compile('[\x00-\x08\x0b-\x1f\x7f​-‏‪-‮⁦-⁩﻿]')
MD_ESC = re.compile(r'([\\`*_\[\]<>|&~#!{}$])')
AUTOLINK = re.compile(r'(?i)(?<![\w.])www\.|:(?=//)')


def clean(s, n=200):
    s = CTRL.sub('?', str(s)).replace('\t', ' ')
    return s if len(s) <= n else s[:n - 1] + '…'


def md(s, n=200):
    """plain text from a log, escaped for the page (a table cell or a line; no autolink: www. and :// broken)"""
    return AUTOLINK.sub(lambda m: m.group(0)[:-1] + '\\' + m.group(0)[-1], MD_ESC.sub(r'\\\1', clean(s, n)))


def code(s, n=220, table=True):
    """a log line in a code span: nothing in it is markup; a table's pipe escaped (a backslash run before it ended
    with a space: GFM reads \\\\| as a backslash and a cell's end)"""
    s = clean(s, n).replace('`', "'")
    return '`' + (re.sub(r'\\+(?=\|)', lambda m: m.group(0) + ' ', s).replace('|', '\\|') if table else s) + '`'


def hms(t):
    if t is None:
        return '-'
    t = int(round(t)) % 86400
    return '%02d:%02d:%02d' % (t // 3600, t // 60 % 60, t % 60)


def dur(s):
    if s is None:
        return '-'
    s = int(round(s))
    sign = '-' if s < 0 else ''
    s = abs(s)
    if s >= 3600:
        return '%s%d:%02d:%02d' % (sign, s // 3600, s // 60 % 60, s % 60)
    return '%s%d:%02d' % (sign, s // 60, s % 60)


def signed_hms(s):
    sign = '+' if s >= 0 else '-'
    s = int(round(abs(s)))
    return '%s%d:%02d:%02d' % (sign, s // 3600, s // 60 % 60, s % 60)


def callout_name(s):
    """a name as sv_down.lua's callouts and down: lines give it: Lua's string.upper (a-z only), 14 characters"""
    return ''.join(c.upper() if 'a' <= c <= 'z' else c for c in (s or ''))[:14]


def vtuple(v):
    m = re.match(r'(\d+)\.(\d+)\.(\d+)', v or '')
    return tuple(int(x) for x in m.groups()) if m else None


def table(head, rows):
    out = ['| ' + ' | '.join(head) + ' |', '|' + '|'.join(' --- ' for _ in head) + '|']
    for r in rows:
        out.append('| ' + ' | '.join(str(c) for c in r) + ' |')
    return out


def counts_text(c, n=12, mark=None):
    items = sorted(c.items(), key=lambda kv: (-kv[1], kv[0]))
    parts = []
    for k, v in items[:n]:
        s = md(k, 60) + (' x%d' % v if v > 1 else '')
        parts.append(('**%s**' % s) if mark and mark(k) else s)
    if len(items) > n:
        parts.append('+%d more' % (len(items) - n))
    return ', '.join(parts) if parts else '-'


# ---- bundles ------------------------------------------------------------------------------------------------------
STAMP = r'(\d{4}-\d\d-\d\d_\d\d-\d\d-\d\d[a-z]?)'
NAMES = [
    ('lua', re.compile(r'AC8SurvivalMode_lua(?:_' + STAMP + r')?\.log', re.I)),
    ('crumbs_prev', re.compile(r'AC8SurvivalMode_crumbs\.prev\.log', re.I)),
    ('crumbs', re.compile(r'AC8SurvivalMode_crumbs(?:_' + STAMP + r')?\.log', re.I)),
    ('native', re.compile(r'AC8SurvivalMode(?:_' + STAMP + r')?\.log', re.I)),
    ('ue4ss_stats', re.compile(r'UE4SS_stats_' + STAMP + r'\.txt', re.I)),
    ('ue4ss', re.compile(r'UE4SS(?:_' + STAMP + r'|\.session)?\.log', re.I)),
    ('session', re.compile(r'session(?:_' + STAMP + r')?\.txt', re.I)),
    ('report', re.compile(r'report\.txt', re.I)),
    ('bundle', re.compile(r'bundle\.txt', re.I)),
    ('zip', re.compile(r'AC8Survival_' + STAMP + r'_.*\.zip', re.I)),
]
MAX_ENTRIES = 5000
READ_ERRORS = (OSError, EOFError, ValueError, zipfile.BadZipFile, zlib.error)     # (a cut or damaged zip, a file gone)


class Src:
    """one file of a bundle, on disk or in a zip; read as a stream"""

    def __init__(self, name, size, opener):
        self.name, self.size, self.opener = name, size, opener

    def blines(self):
        with self.opener() as f:
            for raw in f:
                yield raw

    def lines(self):
        for raw in self.blines():
            yield raw.decode('utf-8', 'replace').rstrip('\r\n')

    def head(self, cap=65536):
        try:
            with self.opener() as f:
                return f.read(cap).decode('utf-8', 'replace')
        except READ_ERRORS:                     # (a small side file of a damaged zip: left out)
            return ''


class Bundle:
    def __init__(self, path):
        self.path = path
        self.files = {}          # kind -> Src
        self.game_logs = []      # Saved/Logs/*.log
        self.crashes = []        # Crashes/UECC-*/* (Src)
        self.others = []         # other sessions seen next to the one read
        self.notes = []
        self.zip = None
        self.stamp = None

    def close(self):
        if self.zip:
            self.zip.close()


def _entries_dir(path):
    out = []
    base = os.path.abspath(path)
    for d, dirs, files in os.walk(base):
        depth = os.path.relpath(d, base).count(os.sep)
        if depth >= 5:
            dirs[:] = []
        dirs[:] = [x for x in dirs if not os.path.islink(os.path.join(d, x))]
        for fn in files:
            full = os.path.join(d, fn)
            if os.path.islink(full) or not os.path.isfile(full):
                continue
            rel = os.path.relpath(full, base).replace(os.sep, '/')
            out.append((rel, os.path.getsize(full), (lambda p=full: open(p, 'rb', buffering=1 << 20))))
            if len(out) > MAX_ENTRIES:
                return out
    return out


def _entries_zip(zf):
    out = []
    for info in zf.infolist()[:MAX_ENTRIES]:
        if info.is_dir():
            continue
        out.append((info.filename.replace('\\', '/'), info.file_size, (lambda i=info: zf.open(i))))
    return out


def _list(path, fileobj=None):
    """(the open zip or None, the entries) of a folder, a zip or one file"""
    if fileobj is not None:                     # (a session zip inside a zipped logs folder)
        z = zipfile.ZipFile(fileobj)
        return z, _entries_zip(z)
    if os.path.isdir(path):
        return None, _entries_dir(path)
    if zipfile.is_zipfile(path):
        z = zipfile.ZipFile(path)
        return z, _entries_zip(z)
    if os.path.isfile(path):
        return None, [(os.path.basename(path), os.path.getsize(path), (lambda p=path: open(p, 'rb', buffering=1 << 20)))]
    raise SystemExit('log_report: no such bundle: %s' % path)


def name_kind(base):
    for kind, rx in NAMES:
        m = rx.fullmatch(base)
        if m:
            return kind, m
    return None, None


def roots_of(entries):
    """the folders each holding one game's logs (several players' logs zipped together; a logs\\ folder is its
    parent's): [] when there's one"""
    roots = set(re.sub(r'(?i)(?:^|/)logs$', '', rel.rpartition('/')[0]) for rel, _, _ in entries
                if name_kind(rel.rsplit('/', 1)[-1])[0] in ('lua', 'native', 'zip'))
    return sorted(roots) if len(roots) > 1 else []


def _owner(rel, roots):
    d = rel.rpartition('/')[0]
    return max((r for r in roots if r == '' or d == r or d.startswith(r + '/')), key=len, default=None)


def bundle_roots(path):
    try:
        z, entries = _list(path)
    except READ_ERRORS:
        return []
    if z:
        z.close()
    return roots_of(entries)


def open_bundle(path, session=None, _depth=0, fileobj=None, root=None):
    b = Bundle(path)
    try:
        b.zip, entries = _list(path, fileobj)
    except READ_ERRORS:
        entries = None
    if entries is None or (b.zip is None and fileobj is None and os.path.isfile(path) and path.lower().endswith('.zip')):
        b.notes.append('%s %s' % (os.path.basename(path), 'could not be read' if os.path.isdir(path) else
                                  'is not a readable zip (cut or damaged): unzip it, or have it sent again'))
        return b
    if root is not None:                        # (one game's folder of several: main's bundle_roots)
        roots = roots_of(entries)
        entries = [e for e in entries if _owner(e[0], roots) == root]
    sessions = defaultdict(lambda: defaultdict(list))
    loose = defaultdict(list)
    for rel, size, opener in entries:
        base = rel.rsplit('/', 1)[-1]
        low = '/' + rel.lower()
        if '/saved/logs/' in low and base.lower().endswith('.log'):
            b.game_logs.append(Src(rel, size, opener))
            continue
        if '/crashes/uecc-' in low:
            b.crashes.append(Src(rel, size, opener))
            continue
        kind, m = name_kind(base)
        if m:
            st = m.group(1) if m.groups() else None
            if kind in ('report', 'bundle', 'crumbs_prev'):
                loose[kind].append(Src(rel, size, opener))
            else:
                sessions[st][kind].append(Src(rel, size, opener))
    logs = [s for s in sessions if sessions[s].get('lua') or sessions[s].get('native')]
    zips = sorted(s for s in sessions if s and sessions[s].get('zip'))
    if session:
        pick = None if session == 'undated' else session
        if pick not in sessions:
            b.notes.append('session %s not found here' % session)
    elif logs:
        dated = sorted(s for s in logs if s)
        pick = dated[-1] if dated else None
    else:
        pick = zips[-1] if zips else None
    if pick is not None and not (sessions[pick].get('lua') or sessions[pick].get('native')) \
            and sessions[pick].get('zip') and _depth == 0:
        z = sessions[pick]['zip'][0]
        if b.zip is None:
            inner = open_bundle(os.path.join(path, z.name), None, 1)
        elif z.size < 1 << 30:
            try:
                with z.opener() as f:
                    data = f.read()
            except READ_ERRORS:
                b.notes.append('%s could not be read inside its zip (cut or damaged): unzip it first' % z.name)
                return b
            inner = open_bundle(os.path.join(path, z.name), None, 1, io.BytesIO(data))
        else:
            b.notes.append('%s is too big to read inside its zip: unzip it first' % z.name)
            return b
        inner.others = sorted(set(s for s in sessions if s and s != pick))
        inner.notes.append('read from %s (%s)' % (z.name, 'the session asked for' if session else 'the newest session zip here'))
        if loose.get('report') and 'report' not in inner.files:
            inner.files['report'] = loose['report'][0]
        b.close()
        return inner
    chosen = sessions.get(pick, {}) if (pick is not None or None in sessions) else {}
    for kind, lst in chosen.items():
        if kind != 'zip':
            b.files[kind] = sorted(lst, key=lambda s: (s.name.count('/'), -s.size))[0]
    for kind, lst in loose.items():
        b.files[kind] = sorted(lst, key=lambda s: s.name.count('/'))[0]
    if not b.files and not b.game_logs:
        b.notes.append('no Survival log found here (AC8SurvivalMode*.log, UE4SS*.log, session or report files)%s'
                       % ('' if os.path.isdir(path) or zipfile.is_zipfile(path) else ': not a folder or a zip that can be read'))
    b.stamp = pick
    b.others = sorted(set(s for s in sessions if s and s != pick)) + \
        (['undated (an older runtime\'s: --session undated)'] if pick is not None and None in logs else [])
    return b


# ---- clocks -------------------------------------------------------------------------------------------------------
TS = re.compile(r'(\d\d):(\d\d):(\d\d)(?:\.(\d{1,7}))? ')


class DayClock:
    """seconds since the game's first day's midnight, from HH:MM:SS that wrap at midnight"""

    def __init__(self, hint=None):
        self.base, self.last, self.hint = None, None, hint

    def __call__(self, sod):
        if self.base is None:
            if self.hint is None:
                self.base = 0
            else:
                day = self.hint // 86400 * 86400
                self.base = day + (86400 if sod < self.hint - day - 6 * 3600 else 0)
        elif sod < self.last - 6 * 3600:
            self.base += 86400
        self.last = sod
        return self.base + sod


def stamped(lines, hint=None):
    """(t, text) for each line; a line without a stamp takes the last one's time"""
    clock = DayClock(hint)
    t = None
    for line in lines:
        m = TS.match(line)
        if m:
            sod = int(m.group(1)) * 3600 + int(m.group(2)) * 60 + int(m.group(3))
            if m.group(4):
                sod += float('0.' + m.group(4))
            t = clock(sod)
            yield t, line[m.end():]
        elif t is not None and line:
            yield t, line


# ---- what a line means --------------------------------------------------------------------------------------------
ISSUE = re.compile(r"\berror\b|\bERROR\b|\bFAILED\b|(?<!\d )\bfailed\b|(?<!\d )\brefused\b|\bnot fired\b|\bNOT \w"
                   r"|\bcould not\b|\bcouldn't\b|\bcan't\b|\bcannot\b|\bcrash|\bexception\b|\bgiven up\b"
                   r"|\bdidn't take\b|(?<!\d )\bdropped\b|\bnil value\b|stack traceback|\btimed out\b|\bdidn't resolve\b")
NOT_ISSUE = re.compile(r"^hud: callout|^subs:|heading error|faults caught|FATAL ERROR|^perf:|^coopfire: \d+ s:"
                       r"|^coop2mp: T4b this minute|^guard: (?:AI path tracking|the guarded event checks), the last"
                       r"|^coop: you are player|^coop:   player|^coop2mp: player \d+'s real plane: \d+ frames|errors? 0\b"
                       r"|can't tell aces|their own game takes their hits|can't be said now")
SHAPE = re.compile(r'\b0x[0-9A-Fa-f]+\b|\b(?=[0-9A-F]*\d)[0-9A-F]{6,16}\b|\d+(?:\.\d+)?')
IDENT = re.compile(r"\b(?=\w*[_\d])\w+\b")          # (an id, a unit, a row, a blueprint: one shape for all)


def shape_of(text):
    return IDENT.sub('X', SHAPE.sub('N', text))[:160]


RE_SV = re.compile(r'RE_SV_\w+')
RE_RAN = re.compile(r'(RE_SV_\w+)(?:(?:(?!RE_SV_)[^;,])*?\b(?:fired|sent)\b| (-?\d+)(?=[);,]|$)| \((fired)\)'
                    r'|:? \((-?\d+)\)|: (-?\d+)\))')    # (its result: "X fired", "(X 1)", "X (1)", "(X: 1)")
RE_BARE = re.compile(r"\((RE_SV_\w+)\)|the host's (RE_SV_\w+) here:")   # ("(RE_SV_AirfieldOpen)": fired; a host's taken here)
RE_NOT = re.compile(r"\b(not fired|NOT fired|dropped|didn't take|held here|waits for|isn't in this build)\b|\bnot\b.*\bagain\b")


def resv_of(text):
    """the RE_SV_* events a Lua line says ran here, and (name, why) for one it says did NOT (the line's first name:
    the others are its explanation's, e.g. 'X dropped here (Y came before it could go)')"""
    m = RE_NOT.search(text)
    if m:
        first = RE_SV.search(text)
        return [], ((first.group(0), (m.group(1) or 'not again').replace('NOT', 'not').replace('held here', 'held'))
                    if first else None)
    ran, nope = [], None
    for m in RE_RAN.finditer(text):
        v = m.group(2) or m.group(4) or m.group(5)
        if v is None or v == '1':
            ran.append(m.group(1))
        elif nope is None:
            nope = (m.group(1), 'not fired: %s' % v)
    ran += [a or b for a, b in RE_BARE.findall(text) if (a or b) not in ran]
    return ran, nope
REPEATING = re.compile(r'ZfaCover|Hunt_|FlightOrders|Radio|Bracket|Push|Cover|Wave|Six|Kulbit|AceTurn|Blink|Regroup'
                       r'|Pincer|Dive|Drag|Jammer|Ecm|LaserOff|Decoy|Tell|Provoke|Pursue|Orders|Retask|Evade|Chase|Salvo|SpecFire|Glitch')

R = re.compile
# (the line's first word, its regex, the event list it goes to, its groups' types: i int, f float, s text, - left out)
NATIVE_RULES = {
    'coop:': [(R(r'coop:   player (\d+) (.*): ([a-z ]+), rtt (\d+) ms; sent \d+ packets \(\d+ KB\), got \d+ \(\d+ KB\), '
                 r'(\d+) resent'), 'rtt', 'issii'),
              (R(r'coop: you are player (\d+); \d+ enemy streams bound \(\d+ moves, (\d+) failed\); (\d+) bad packets'
                 r'.*?lateness (\d+) ms'), 'streams', 'iiii'),
              (R(r'coop: joined: (.*) \(\w+, mod (\S+)\) as player (\d+)'), 'joined', 'ssi'),
              (R(r'coop: player (\d+): link (up|lost)'), 'link', 'is'),
              (R(r'coop: player (\d+) (gone) \(nothing for \d+ s\)'), 'link', 'is'),
              (R(r'coop: (.+ is also the \w+);'), 'twohosts', 's'),
              (R(r'coop: refused (.+?): their Survival is (\S+), this game.s (\S+)'), 'refused_join', 'sss'),
              (R(r'(coop: reliable queue to player .*)'), 'link_note', 's')],
    'minigame:': [(R(r'minigame: type (\d+) (starts|deactivated|ends)'), 'minigame', 'is')],   # (deactivated: solo's start)
    'units:': [(R(r"units: the last minute: (\d+) SV_UnitAlive asks, (\d+) us each on average \(worst (\d+) us\); "
                  r"the phase's list up to (\d+)"), 'units', 'iiii')],
    'frames:': [(R(r'frames: the last minute: \d+ frames while a plane flew \((\d+) fps\), ([\d.]+) ms on average, '
                   r'95% under (\d+) ms(?: or more)?, worst (\d+) ms; (\d+) over 50 ms, (\d+) over 100 ms'), 'frames', 'ifiiii')],
    'leaderboard:': [(R(r'leaderboard: (run sent, status \d+|sending a run)'), 'lb_native', 's'),
                     (R(r'leaderboard: the game started: build hash ([0-9a-f]+)'), 'n_hash', 's')],
    'AC8': [(R(r'AC8 Survival Mode runtime (\S+)'), 'n_runtime', 's')],
    'logs:': [(R(r"(logs: (?:UE4SS\.log's copy|session .* zipped|this session).*)"), 'logs', 's')],
}
LUA_RULES = {
    'loaded,': [(R(r'loaded, version (\S+)'), 'loaded', 's')],
    'round': [(R(r'round (\d+): (\d+) aircraft: (.*)$'), 'start', 'iis'), (R(r'round (\d+) clear; round \d+ in'), 'clear', 'i'),
              (R(r'round (\d+): a strike package'), 'strike', 'i')],
    'credits:': [(R(r"credits: \+\d+ \(round (\d+) cleared \(the host's round\)\)"), 'jclear', 'i')],
    'stats:': [(R(r'stats: round (\d+) \((.*?), (.*?), (\d+) players?\)(?: \(cut short: .*?\))?: length (\d+) s '
                  r'\((\d+) s at the airfield\), '
                  r'(\d+) waves?; aircraft down (\d+) \(yours (\d+)\)'), 'stats', 'issiii-ii')],
    'music:': [(R(r'music: track clock (held) \(landing store\)'), 'store', 's'), (R(r'music: track clock (running)'), 'store', 's')],
    'revive:': [(R(r"revive: player (\d+) revived player (\d+) for (\d+) \(the run's revive (\d+)(?:, their (\d+))?; "
                   r"round (\d+)'s price\)"), 'revive', 'iiiisi'),
                (R(r"revive: (player \S+'s revive of player \S+ refused: .*|asked the host to revive .*|player \d+ revived by .*"
                   r"|the host refused your revive .*|no answer from the host .*|player \d+'s revive refunded .*)"), 'revive_note', 's')],
    'shop:': [(R(r'shop: Revive: (.*(?:REVIV|ZOLLARS|PLAYER|DOWN|LINK|YOURSELF|PRICE|AIRFIELD).*)'), 'revive_shop', 's')],
    'coop:': [(R(r'coop: player (\d+) is (.+?)(?:, Survival | \(Survival )([^\s,()]+)'), 'player_is', 'iss'),
              (R(r'coop: player (\d+): sys\|([a-z]+)(?:\|(.*))?$'), 'sys', 'iss'),
              (R(r'coop: you are player (\d+)\b'), 'youare', 'i'),
              (R(r'coop: (.+) tried to join with Survival (\S+) \(yours (\S+)\): refused'), 'refused_join', 'sss'),
              (R(r'coop: migration: ((?!the next hosts).*)'), 'migration', 's'),
              (R(r"coop: ((?:migration: )?the host \(.+?\) left its run in round \d+ \(hl\|left\).*)"), 'leftnote', 's'),
              (R(r"coop: (out of Survival's level: every joiner told.*)"), 'leftnote', 's'),
              (R(r'coop: (another host \(.*)'), 'twohosts', 's'),
              (R(r"(coop: the host's rocket .*)"), 'rocket', 's'),
              (R(r"coop: the host's (VALKA) mood on"), 'valka', 's'),
              (R(r"(coop: .*(?:Alicorn|joiners' hits dealt here).*)"), 'alicorn', 's')],
    'down:': [(R(r"down: you're down at (\d+) HP in round (\d+)"), 'selfdown', 'ii'),
              (R(r'down: player (\d+) \((.*)\) is down'), 'otherdown', 'is'),
              (R(r'down: run over in round \d+: (.*)$'), 'downover', 's'),
              (R(r"(down: the host(?:'s link| migration).*)"), 'down_note', 's')],
}


def conv(m, types):
    out = []
    for g, ty in zip(m.groups(), types):
        if ty == 'i':
            out.append(int(g) if g is not None else None)
        elif ty == 'f':
            out.append(float(g))
        elif ty == 's':
            out.append(g or '')
    return tuple(out)


R_CALL = R(r"hud: callout '(.*?)'(?: / '(.*)')?$")
R_PERF = R(r'perf: tick avg ([\d.]+) ms \(halves [\d.]+ \+ [\d.]+\), worst half ([\d.]+) ms .*? over (\d+) ticks; parts '
           r'\(ms a tick / worst, share\): (.*?); untimed')
R_PART = R(r'([a-z][a-z0-9 /]*?) ([\d.]+)/(\d+) (\d+)%')
R_UALIVE = R(r'SV_UnitAlive ([\d.]+) a tick ([\d.]+) ms \(worst (\d+)\)')
R_PROBE = R(r'(SV_\w+)=(-?\d+)')
R_LB_RUNOVER = R(r'leaderboard: run over \(([^)]*)\): round (\d+), score (\d+), (\d+) air / (\d+) ground kills, '
                 r'(\d+) specials beaten, ([\d:]+)')
R_LB_ANSWER = R(r'leaderboard: (the run|a waiting run|a kept run .*?)(?:: the server)? answered (-?\d+)'
                r'(?: \((?:[^()]|\([^)]*\))*\))?:(?: (.*))?$')  # (a network error's status is negative, its why in brackets)
R_LB_REFINE = R(r"leaderboard: co-op run \w+ (NOT stored|stored: it replaced|is on the board already)")


def lb_kind(who, st, body):
    """what the board did with a run, from an answer line (sv_leaderboard.lua LB.poll / keptAnswer)"""
    if who.startswith('a kept run'):
        for k, w in (('taken', 'stored'), ('NOT stored', 'NOT stored'), ('a duplicate', 'duplicate (kept to resend)'),
                     ('still an unknown', 'refused (unknown build, kept)'), ('played on other', 'refused (other files, kept)'),
                     ('refused', 'refused (%d)' % st)):
            if body.startswith(k):
                return w + (' (replaced)' if w == 'stored' and 'it replaced' in body else '')
        return 'not sent (network)' if st < 0 else 'no answer (%d, kept)' % st
    if st < 0 or not body.strip():
        return 'not sent (network)'
    if st == 200:
        return 'duplicate' if '"duplicate":true' in body else 'stored (replaced)' if '"replaced":true' in body else 'stored'
    return 'no answer (%d, kept)' % st if st == 429 or st >= 500 else 'refused (%d)' % st
R_CENSUS = R(r"allies: (BP_\w*uavc\w*?)_(\d+) \((E_Unit_\w+)\) at round (\d+)'s level")
R_KM = R(r'\((-?\d+(?:\.\d+)?), (-?\d+(?:\.\d+)?)\) km')
R_BLAST = R(r'dive: Helios blast (\d+) \((.*?)\) at \((-?[\d.]+), (-?[\d.]+)\) km (-?\d+) m: (\d+) enemy aircraft down')
R_PARKED = R(r"carrier: (.+?): (\d+) (?:of this game's switched-off |\w+ )?(?:parked )?ZFA-44s of ship (\d+) finished off(.*)$")
R_STILLUP = R(r'escort: (E_Unit_\w+) \((.*?)\) still has (\d+) up after (\d+) s')
R_TANK = R(r'special: Alicorn tank (\w+) hit: -(\d+) \((\d+) left\)')
R_COREHIT = R(r'special: Alicorn core hit: -(\d+) \((\d+) left(?:, (\d+)%)?')
R_UE_DEDUP = R(rb'---- the line above (\d+) more times')
R_UE_MOD = R(rb"Mod '([^']{1,80})' has enabled\.txt, starting mod")
R_UE_SRC = R(rb'\[Lua\] \[([^\]]{1,60})\]')
UE_ERR = R(rb'[Ee]rror|ERROR|[Ff]ailed|[Ee]xception|stack traceback|attempt to|[Ff]atal')
UE_SHAPE = R(rb'(?<![A-Za-z])\d+')
GAME_ERR = R(r'Error:|Fatal|LowLevelFatalError|Assertion failed|Unhandled Exception|Critical error')
CALLS = [   # (a callout's first text, its second, the event: down / back / ...)
    (R(r"YOU'RE DOWN$"), None, 'down', lambda a, s: ('self', None, 'callout')),
    (R(r'(.+) DOWN$'), R(r'LAND AND REVIVE'), 'down', lambda a, s: ('other', a[:-5], 'callout')),
    (R(r'BACK IN THE FIGHT$'), None, 'back', lambda a, s: ('self', None, s[11:] if s.startswith('REVIVED BY ') else s)),
    (R(r'(.+) BACK$'), R(r'REVIVED BY '), 'back', lambda a, s: ('other', a[:-5], s[11:])),
    (R(r'CO-OP: YOU ARE THE HOST$'), None, 'role', lambda a, s: ('host', 'the callout CO-OP: YOU ARE THE HOST')),
    (R(r'YOU ARE THE NEW HOST$'), None, 'migration', lambda a, s: ('this game is the new host (callout)',)),
    (R(r'CO-OP: TWO HOSTS$|.* HOSTS TOO$'), None, 'twohosts', lambda a, s: (a + (' / ' + s if s else ''),)),
    (R(r'CO-OP: .* \(HOST\) IS GONE$|.*\(HOST\) LEFT THE RUN$'), None, 'migration', lambda a, s: (a + (' / ' + s if s else ''),)),
    (R(r'CO-OP LINK (LOST|BACK)$'), None, 'callink', lambda a, s: (a, s)),
    (R(r'(.+) JOINED$'), R(r'PLAYERS'), 'calljoin', lambda a, s: (a[:-7], s)),
    (R(r'(.+) LEFT$'), R(r'^$'), 'calljoin', lambda a, s: (a[:-5], 'left')),
    (R(r'REFUSED (.+)$'), None, 'refused_join', lambda a, s: (a[8:], s, '')),
]

# ---- the 0.74.52 checklist (HISTORY.md 0.74.51 / 0.74.52, docs/re/LAG.md, ZFA44.md, COOP.md, ALICORN.md, ...) -------
# (fix, area, log, the line (a regex at its start, after the time), its anchor (a literal in the code that prints it:
# --check-anchors), a sample (the regex must take it), expect: yes every run, when when it happens, no trouble if seen)
CHECKS = [
    ('lag-1', 'lag', 'native', r'spawner: LiveUnitSpawner .*checked through GUObjectArray: yes', 'checked through GUObjectArray: %s', 'spawner: LiveUnitSpawner 1A, global phase 2B, world data 3C; checked through GUObjectArray: yes', 'yes'),
    ('lag-1', 'lag', 'native', r'units: the last minute: \d+ SV_UnitAlive asks', 'units: the last minute: %u SV_UnitAlive asks', "units: the last minute: 120 SV_UnitAlive asks, 14 us each on average (worst 90 us); the phase's list up to 40 long", 'yes'),
    ('joiner-4', 'lag', 'native', r'frames: the last minute: \d+ frames while a plane flew', 'frames: the last minute: %u frames while a plane flew', 'frames: the last minute: 1800 frames while a plane flew (30 fps), 33.3 ms on average, 95% under 40 ms, worst 90 ms; 0 over 50 ms, 0 over 100 ms; 0 gaps over 2 s not counted (a pause, a load) (joiner-4)', 'yes'),
    ('lag-2', 'lag', 'lua', r'alive: round \d+: .*\(lag-2\) the asks took', '(lag-2) the asks took %.1f ms in all', "alive: round 3: 10 native SV_UnitAlive asks (0 at once: a plane of the flight seen down), 2 kept answers used (0 past the tick's budget); (lag-2) the asks took 1.0 ms in all", 'yes'),
    ('lag-3', 'lag', 'lua', r"allies: the airfield defences' actors from their objects kept at their spawn", "allies: the airfield defences' actors from their objects kept at their spawn", "allies: the airfield defences' actors from their objects kept at their spawn: 4 for 4 up, no walk (lag-3)", 'when'),
    ('lag-5', 'lag', 'lua', r"allies: .*'s ESM fields: the newest \d+ kept", "'s ESM fields: the newest %d kept, the oldest let go (lag-5)", "allies: VOID WATCHER 1's ESM fields: the newest 32 kept, the oldest let go (lag-5)", 'when'),
    ('lag-8', 'lag', 'native', r"logs: UE4SS\.log's copy: \d+ MB read", "logs: UE4SS.log's copy: %u MB read", "logs: UE4SS.log's copy: 5 MB read, 1 MB written, 9 lines, 4 of them repeats collapsed, 0 past the 64 MB cap", 'when'),
    ('zfa-1', 'ZFA-44s', 'lua', r'carrier: a ZFA-44 finished off \(', 'carrier: a ZFA-44 finished off (%s): its health read %s after ModifyHealth', 'carrier: a ZFA-44 finished off (carrier leaving): its health read 0 after ModifyHealth (damage event), as every one this level should', 'when'),
    ('zfa-1', 'ZFA-44s', 'lua', r'carrier: a ZFA-44 \S+ \(.*\) could not be finished', 'could not be finished (health %s after ModifyHealth and ApplyDamage): switched off', 'carrier: a ZFA-44 2147 (dive) could not be finished (health 2700 after ModifyHealth and ApplyDamage): switched off', 'no'),
    ('zfa-2', 'ZFA-44s', 'lua', r'dive: a ZFA-44 of dive \d+ onto the nearest enemy aircraft', 'dive: a ZFA-44 of dive %d onto the nearest enemy aircraft', 'dive: a ZFA-44 of dive 1 onto the nearest enemy aircraft, 4.2 km off (about 13 s at 1200 km/h; 13.3 km in its 40 s)', 'when'),
    ('zfa-2', 'ZFA-44s', 'lua', r'dive: Helios blast \d+ .*; its ZFA-44 (?:down|NOT down)', '(dive %d: %d down); its ZFA-44 %s', "dive: Helios blast 1 (in reach) at (1.0, 2.0) km 900 m: 2 enemy aircraft down, 0 aces' or specials' hurt (dive 1: 2 down); its ZFA-44 down", 'when'),
    ('zfa-3', 'ZFA-44s', 'lua', r'carrier: VAMPIRES \S+ \S+ at \(', 'carrier: VAMPIRES %s %s at (%.1f, %.1f) km', 'carrier: VAMPIRES E_Unit_01_drone_5_0 2147 at (1.0, -2.0) km 900 m, 700 km/h, health 2700 (escort)', 'when'),
    ('zfa-4', 'ZFA-44s', 'lua', r'special: shuttle and pad off: the shuttle (?:killed|NOT killed) \(', '("NOT killed (health " .. tostring(h1) .. " after ModifyHealth and ApplyDamage)")', "special: shuttle and pad off: the shuttle killed (damage event); 22 objects hidden (20 of them the pad's own, as spawned)", 'when'),
    ('rockets', 'Spaceport', 'lua', r'special: round \d+, the Spaceport Retake starts: \d+ spawns and checks queued', 'the Spaceport Retake starts: %d spawns and checks queued', 'special: round 50, the Spaceport Retake starts: 40 spawns and checks queued (a spawn or 4 checks a tick)', 'when'),
    ('rockets', 'Spaceport', 'lua', r'special: rocket \S+(?: and B)?: \S+ \(', 'special: rocket %s: %s (%s; line %s; %s)', 'special: rocket A: warning (radio RE_SV_SpRadioWarn 1; line 1; sub)', 'when'),
    ('rockets', 'Spaceport', 'lua', r"coop: the host's rocket [AB]", "coop: the host's rocket %s: %s%s", "coop: the host's rocket B: escaped at 20200 m", 'when'),
    ('rockets', 'Spaceport', 'lua', r'special: rocket [AB] left its pad: its launch took here', 'left its pad: its launch took here', 'special: rocket A left its pad: its launch took here', 'when'),
    ('down-1', 'DOWN host', 'lua', r"aces: .* not put back onto you: you're down", "not put back onto you: you're down (its target %s", "aces: BP_x not put back onto you: you're down (its target BP_y, left as it is; 1 planes so far)", 'when'),
    ('down-1', 'DOWN host', 'lua', r"coop: you're down: \d+ flights? .*of them again: \d+ planes? back on your hidden plane", 'of them again: %d plane%s back on your hidden plane', "coop: you're down: 2 flights (4 planes) sent after the other players instead (1 of them again: 2 planes back on your hidden plane)", 'no'),
    ('down-1', 'DOWN host', 'lua', r"allies: you're down: the enemies' hunts for the allied aircraft wait", "allies: you're down: the enemies' hunts for the allied aircraft wait for your revive", "allies: you're down: the enemies' hunts for the allied aircraft wait for your revive", 'when'),
    ('down-1', 'DOWN host', 'lua', r'director: .*: player \d+ is down or landed: its aim on them ends early', 'is down or landed: its aim on them ends early', 'director: ERA_Unit_01_Dep_Air0: player 1 is down or landed: its aim on them ends early', 'when'),
    ('down-1', 'DOWN host', 'lua', r"stats: you're down: your flying isn't measured", "stats: you're down: your flying isn't measured", "stats: you're down: your flying isn't measured (tails, engagements, P6's habits) until your revive", 'when'),
    ('down-2', 'DOWN joiner', 'lua', r"down: the host's link is gone and a host migration is under way", "down: the host's link is gone and a host migration is under way", "down: the host's link is gone and a host migration is under way: the revives' floor (0.1 HP) and the run's hold stay on through it", 'when'),
    ('revive', 'revives', 'lua', r"revive: player \S+'s revive of player \S+ refused: ", 'revive of player %s refused: %s%s', "revive: player 2's revive of player 3 refused: THEIR LINK IS LAGGING: TRY AGAIN (their last state 900 ms old)", 'when'),
    ('revive', 'revives', 'lua', r"revive: player \d+ revived player \d+ for \d+ \(the run's revive \d+, their \d+", "(the run's revive %d, their %d; round %d's price)", "revive: player 2 revived player 3 for 9500 (the run's revive 1, their 1; round 50's price)", 'when'),
    ('revive', 'revives', 'lua', r'revive: slots changed hands', 'revive: slots changed hands, each player', "revive: slots changed hands, each player's own revives follow them: player 3 (E, was C): 0", 'when'),
    ('board-1', 'leaderboard', 'lua', r'leaderboard: co-op run \w+ NOT stored', 'NOT stored: the leaderboard keeps another copy of it', 'leaderboard: co-op run 2498a83c NOT stored: the leaderboard keeps another copy of it, as far or further', 'no'),
    ('board-1', 'leaderboard', 'lua', r'leaderboard: co-op run \w+ stored: it replaced', "stored: it replaced the board's shorter copy of the run", "leaderboard: co-op run 2498a83c stored: it replaced the board's shorter copy of the run (x)", 'when'),
    ('board-2', 'co-op', 'lua', r"coop: out of Survival's level: every joiner told this game left its run", "coop: out of Survival's level: every joiner told this game left its run in round %d", "coop: out of Survival's level: every joiner told this game left its run in round 51 (hl|51|left; 2 linked): ", 'when'),
    ('board-2', 'co-op', 'lua', r'coop: migration: the host \(.*\) left its run in round \d+ \(hl\|left\)', 'left its run in round %d (hl|left): the next host now', 'coop: migration: the host (Ana) left its run in round 51 (hl|left): the next host now, not after 30 s of silence', 'when'),
    ('board-3', 'co-op', 'lua', r'coop: another host \(.*\) heard while this game hosts', 'coop: another host (%s) heard while this game hosts a run', 'coop: another host (Bo) heard while this game hosts a run with 4 players: most likely a dropped joiner', 'no'),
    ('board-4', 'co-op', 'lua', r'coop: the host took \S+ off \(.*taken down here, its unit off', 'taken down here, its unit off', "coop: the host took ERA_Unit_01_Dep_Air0 off (RE_SV_FlightOff_01): 2 of its copies here off, unpaid; 2 taken down here, its unit off this game's spawner list 2 s on", 'when'),
    ('board-5', 'co-op', 'native', r'coop: reliable queue to player \d+ \(.*\) full', 'coop: reliable queue to player %d (%s) full', 'coop: reliable queue to player 2 (Bo) full (256 messages waiting for their acks): 3 message(s) dropped since the last such line', 'no'),
    ('board-6', 'co-op', 'lua', r'coop: player \d+ asked for the whole picture; this game has no run', 'asked for the whole picture; this game has no run', 'coop: player 2 asked for the whole picture; this game has no run (its level loading): no picture sent', 'when'),
    ('alicorn', 'Alicorn', 'lua', r"special: the Alicorn's core sized: ", "special: the Alicorn's core sized: %s", "special: the Alicorn's core sized: 20 missiles (10 + 3.3 x 3 other players flying), 9600 health", 'when'),
    ('alicorn', 'Alicorn', 'lua', r"special: the Alicorn's core open with \d+ health", "special: the Alicorn's core open with %.0f health", "special: the Alicorn's core open with 9600 health: CORE 100% on every player's row", 'when'),
    ('alicorn', 'Alicorn', 'lua', r'special: Alicorn core hit: -\d+', 'special: Alicorn core hit: -%.0f (%.0f left%s)', 'special: Alicorn core hit: -480 (9120 left, 95%)', 'when'),
    ('alicorn', 'Alicorn', 'lua', r"coop: the joiners' hits dealt here in the last 60 s", "coop: the joiners' hits dealt here in the last 60 s", "coop: the joiners' hits dealt here in the last 60 s (health x 10): player 4: 3 hits (3 taken, 0 refused, 0 dropped), 900", 'when'),
    ('alicorn', 'Alicorn', 'lua', r"coop: the host's \S+ here bound with the host's health", "here bound with the host's health, which came first", "coop: the host's SV_Unit_Alicorn here bound with the host's health, which came first (core 31250 -> 9600)", 'when'),
    ('alicorn', 'Alicorn', 'lua', r"special: the Alicorn's (?:hull|copy here) at \(", "special: the Alicorn's hull at (%.1f, %.1f) km", "special: the Alicorn's hull at (-21.0, -5.4) km, heading 90, its out leg", 'when'),
    ('shuttle', 'shuttle', 'lua', r'special: shuttle liftoff replay(?:ed here, try \d+ of \d+| waits)', 'special: shuttle liftoff replayed here, try %d of %d', 'special: shuttle liftoff replayed here, try 1 of 3: RE_SV_ShuttleT_136 1, the climb 1', 'when'),
    ('shuttle', 'shuttle', 'lua', r"special: shuttle lifted off here at the replay's try \d+", "special: shuttle lifted off here at the replay's try %d", "special: shuttle lifted off here at the replay's try 1 (SV_ShuttleLaunched 1, SV_ShuttleRound 1)", 'when'),
    ('shuttle', 'shuttle', 'lua', r'special: shuttle liftoff not replayed', 'special: shuttle liftoff not replayed', 'special: shuttle liftoff not replayed here: it never left its pad here in 3 tries', 'no'),
    ('shuttle', 'shuttle', 'lua', r"special: RE_SV_ShuttleRemove (?:didn't take here|fired again here)", "special: RE_SV_ShuttleRemove didn't take here", "special: RE_SV_ShuttleRemove didn't take here (SV_ShuttleRound 1, SV_ShuttleLaunched 1): fired again here once your STORE is shut", 'when'),
    ('shuttle', 'shuttle', 'lua', r'special: shuttle after its countdown, round \d+: ', 'special: shuttle after its countdown, round %d: SV_ShuttleLaunched %s', 'special: shuttle after its countdown, round 2: SV_ShuttleLaunched 1, SV_ShuttleRound 1; the shuttle 2.0 km from its pad', 'when'),
    ('shuttle', 'shuttle', 'lua', r"round \d+: bomber flight .*\(SV_ShuttleRound \d+: its orders are the shuttle's\)", "(SV_ShuttleRound %d: its orders are the shuttle's)", "round 2: bomber flight EA_Unit_01_Air0 as f15e_common_sv (2 set), 30 km out at bearing 106, 0.7 km up: 2 aircraft up (SV_ShuttleRound 1: its orders are the shuttle's)", 'when'),
]
CHECK_RX = [(c, re.compile(c[3])) for c in CHECKS]
CHECK_BY = defaultdict(list)
for _i, (_c, _rx) in enumerate(CHECK_RX):
    CHECK_BY[(_c[2], _c[3].split(' ', 1)[0].replace('\\', ''))].append((_i, _rx))


class Game:
    def __init__(self, bundle, idx):
        self.b, self.idx = bundle, idx
        self.version = self.runtime = self.hash = self.steam = self.run_id = None
        self.role, self.role_why, self.slot, self.offset, self.aligned = None, '', None, 0.0, None
        self.first = self.last = self.ue = None
        self.ev = defaultdict(list)
        self.issues = {}                     # (log, shape) -> [count, first, last, the first line]
        self.checks, self.check_first, self.names = Counter(), {}, {}
        self.game_errs, self.lines, self.label, self.crumbs_last, self.occupants = Counter(), Counter(), '', [], {}

    def _mark(self, t):
        self.first = t if self.first is None or t < self.first else self.first
        self.last = t if self.last is None or t > self.last else self.last

    def ref(self, t):
        return None if t is None else t - self.offset

    def at(self, t):
        return '-' if t is None else hms(t - self.offset) + (' [%s]' % hms(t) if self.offset else '')

    def name_of(self, slot, t=None):
        """the slot's player at t (its latest name first seen by then), else every name it had"""
        occ = self.occupants.get(slot)
        if t is not None and occ:
            best = [n for t0, n in occ if t0 <= t + 1]
            if best:
                return best[-1]
        n = self.names.get(slot)
        return ' / '.join(sorted(n)) if n else ('player %s' % slot)

    def line(self, where, t, text, rules):
        """one line of a log: the issues, the checklist, the rules; True when a rule took it"""
        self.lines[where] += 1
        self._mark(t)
        if ISSUE.search(text) and not NOT_ISSUE.search(text):
            key = (where, shape_of(text))
            e = self.issues.get(key)
            if e:
                e[0] += 1
                e[2] = t
            else:
                self.issues[key] = [1, t, t, text]
        cat = text.split(' ', 1)[0]
        for i, rx in CHECK_BY.get((where, cat), ()):
            if rx.match(text):
                self.checks[i] += 1
                self.check_first.setdefault(i, t)
        for rx, key, types in rules.get(cat, ()):
            m = rx.match(text)
            if m:
                self.ev[key].append((t,) + conv(m, types))
                return True
        return False

    def parse_native(self, src):
        for t, text in stamped(src.lines()):
            self.line('native', t, text, NATIVE_RULES)

    def parse_lua(self, src):
        for t, text in stamped(src.lines(), self.first):
            if 'RE_SV_' in text and not text.startswith('round probe'):
                ran, nope = resv_of(text)
                if ran or nope:
                    self.ev['resv'].append((t, ran, "the host's" in text or text.startswith('coop: the host took'), nope))
            if not self.line('lua', t, text, LUA_RULES):
                h = LUA.get(text.split(' ', 1)[0])
                if h:
                    h(self, t, text)

    def l_round(self, t, text):
        if text.startswith('round probe: flags '):
            self.ev['probe'].append((t, dict((k, int(v)) for k, v in R_PROBE.findall(text))))

    def l_hud(self, t, text):
        m = R_CALL.match(text)
        if not m:
            return
        a, s = m.group(1), m.group(2) or ''
        mm = re.match(r'(SPECIAL )?ROUND (\d+)( COMPLETE)?$', a)
        if mm:
            if mm.group(3):
                self.ev['call_clear'].append((t, int(mm.group(2))))
            else:
                self.ev['call_round'].append((t, int(mm.group(2)), bool(mm.group(1)), s))
            return
        for ra, rs, key, f in CALLS:
            if ra.match(a) and (rs is None or rs.search(s)):
                self.ev[key].append((t,) + f(a, s))
                break
        for key, rx in (('rocket', r'ROCKET|SPACEPORT|RETAKE'), ('alicorn', r'ALICORN|CORE'), ('shuttle', r'SHUTTLE')):
            if re.search(rx, a):
                self.ev[key].append((t, 'callout: ' + a + (' / ' + s if s else '')))

    def l_lb(self, t, text):
        body = text[13:]
        m = re.match(r"leaderboard: (?:Steam name '(.*)'|this build's hash is ([0-9a-f]{16,}))$", text)
        if m:
            self.steam, self.hash = m.group(1) or self.steam, m.group(2) or self.hash
            return
        m = re.match(r"leaderboard: co-op run (\w+)(?: started: this game (hosts) it|: the host's \(the host sends it\))", text)
        if m:
            self.run_id = m.group(1)
            self.ev['role'].append((t, 'host' if m.group(2) else 'joiner', ('hosts co-op run ' if m.group(2) else
                                                                           "in the host's co-op run ") + m.group(1)))
            self.ev['runstart'].append((t, 'co-op run %s (%s)' % (m.group(1), "this game hosts it" if m.group(2) else "the host's")))
        elif R_LB_RUNOVER.match(text):
            self.ev['runover'].append((t, 'run over (%s): round %s, score %s, %s air / %s ground, %s specials, %s'
                                       % R_LB_RUNOVER.match(text).groups()))
        elif R_LB_ANSWER.match(text):
            m = R_LB_ANSWER.match(text)
            self.ev['lb_answer'].append((t, lb_kind(m.group(1), int(m.group(2)), m.group(3) or ''), m.group(3) or ''))
        elif not re.search(r'sending the run|resending|NOT stored|stored:|on the board already|kept to resend|takes it over'
                           r'|carried on here|lone takeover|refused_runs|not resent|not sent|a co-op run; the host sends', text):
            return
        self.ev['lb'].append((t, 'lua', body))
        m = R_LB_REFINE.match(text)
        if m:                                   # (the answer just before it, refined: one answer, not two)
            k = {'NOT stored': 'NOT stored', 'is on the board already': 'on the board already'}.get(m.group(1), 'stored (replaced)')
            k += ' (kept to resend)' if k == 'NOT stored' and 'to send again' in text else ''
            a = self.ev['lb_answer']
            if a and t - a[-1][0] <= 10 and a[-1][1] in ('duplicate', 'stored', 'stored (replaced)'):
                a[-1] = (a[-1][0], k, a[-1][2])
            else:
                a.append((t, k, body))
        if 'takes it over (host migration)' in text:
            self.ev['role'].append((t, 'host (migration)', 'took the run over by host migration'))

    def l_special(self, t, text):
        if 'shuttle' in text or 'Shuttle' in text:
            if not re.match(r'special: shuttle \d+ s in:', text):
                self.ev['shuttle'].append((t, text))
        elif 'rocket' in text or 'Retake' in text or "retake's" in text:
            self.ev['rocket'].append((t, text))
        elif 'Alicorn' in text:
            m = R_TANK.match(text)
            m2 = R_COREHIT.match(text)
            if m:
                self.ev['tank'].append((t, m.group(1), int(m.group(2)), int(m.group(3))))
            elif m2:
                self.ev['corehit'].append((t, int(m2.group(1)), int(m2.group(2)), m2.group(3)))
            elif not re.search(r"railgun in \d+ s: warned|deck launch \d+:|deck waits|pooled aircraft|'s rows:|searchlight", text):
                self.ev['alicorn'].append((t, text))

    def l_zfa(self, t, text):
        m = R_CENSUS.match(text)
        if m:
            self.ev['census'].append((t, int(m.group(4)), m.group(1) + '_' + m.group(2), m.group(3)))
            return
        if not text.startswith(('carrier:', 'dive:', 'escort: E_Unit')) or (text.startswith('carrier: VAMPIRES') and ' escort ' in text):
            return                                              # (every few seconds: their escort orders)
        m = R_BLAST.match(text)
        if m:
            self.ev['blast'].append((t, float(m.group(3)), float(m.group(4)), int(m.group(6)), 'NOT down' if
                                     'its ZFA-44 NOT down' in text else ('down' if 'its ZFA-44 down' in text else '?')))
        elif text.startswith('carrier: launched ZFA-44s +'):
            pos = R_KM.findall(text)
            self.ev['launched'].append((t, len(pos), pos))
        elif R_STILLUP.match(text):
            m = R_STILLUP.match(text)
            self.ev['stillup'].append((t, m.group(1), m.group(2), int(m.group(3))))
        elif R_PARKED.match(text):
            m = R_PARKED.match(text)
            nc, tried = re.search(r'(\d+) could not be', m.group(4)), re.match(r' \((\d+) tried\)', m.group(4))
            n = int(m.group(2))                 # (ZLAUNCH.offKill's: N of the switched-off finished off (M tried))
            self.ev['finished'].append((t, n, int(nc.group(1)) if nc else max(0, int(tried.group(1)) - n) if tried else 0, m.group(1)))
        elif 'could not be finished' in text:
            self.ev['notfinished'].append((t, text))
        elif text.startswith('carrier: a ZFA-44 finished off'):
            self.ev['finished_one'].append((t, text))
        elif re.match(r'carrier: VAMPIRES \S+ \S+ at \(', text):
            p = R_KM.search(text)
            if p:
                self.ev['zpos'].append((t, float(p.group(1)), float(p.group(2))))
        elif re.search(r'on station|launches its ZFA-44s|sunk|gone \(|leaving|dive: over|dive: round', text):
            self.ev['carrier'].append((t, text))

    def l_perf(self, t, text):
        m = R_PERF.match(text)
        if m:
            parts = sorted(((p[0].strip(), float(p[1]), int(p[2])) for p in R_PART.findall(m.group(4))), key=lambda x: -x[1])
            mem = re.search(r'memory (\d+) MB', text)
            self.ev['perf'].append({'t': t, 'avg': float(m.group(1)), 'worst': float(m.group(2)), 'ticks': int(m.group(3)),
                                    'parts': parts[:3], 'mem': int(mem.group(1)) if mem else None})
        elif text.startswith('perf: lists:') and self.ev['perf']:
            p = self.ev['perf'][-1]
            u = R_UALIVE.search(text)
            h = re.search(r'Lua heap ([\d.]+) MB', text)
            if u:
                p['ua'] = (float(u.group(1)), float(u.group(2)), int(u.group(3)))
            if h:
                p['heap'] = float(h.group(1))

    def parse_crumbs(self, src):
        for t, text in stamped(src.lines(), self.first):
            self.lines['crumbs'] += 1
            m = re.match(r't\d+ (.*)$', text)
            body = m.group(1) if m else text
            mm = re.match(r'lua: event (RE_SV_\w+): (-?\d+)', body)
            if mm:
                self.ev['crumb_ev'].append((t, mm.group(1), int(mm.group(2))))
            self.crumbs_last = (self.crumbs_last + [(t, body)])[-8:]

    def scan_ue4ss(self, src):
        """UE4SS.log streamed: its line shapes counted (the copy's collapsed runs given back), its sources and errors"""
        shapes, srcs, errs, mods = Counter(), Counter(), {}, []
        n = nbytes = started_over = cap = 0
        prev_text = prev_shape = prev_src = first_stamp = last_stamp = None
        for raw in src.blines():
            nbytes += len(raw)
            line = raw.rstrip(b'\r\n')
            if not line:
                continue
            text = line
            if line[:1] == b'[':
                j = line.find(b'] ', 1, 40)
                if j > 0 and line[1:2].isdigit():
                    last_stamp, text = line[1:j], line[j + 2:]
                    first_stamp = first_stamp or last_stamp
            if text == prev_text:
                n += 1
                shapes[prev_shape] += 1
                srcs[prev_src] += 1
                continue
            if text[:5] == b'---- ':
                m = R_UE_DEDUP.match(text)
                if m and prev_shape is not None:
                    k = int(m.group(1))
                    n += k
                    shapes[prev_shape] += k
                    srcs[prev_src] += k
                started_over += text.startswith(b'---- UE4SS.log started over')
                cap += text.startswith(b'---- the copy of UE4SS.log stops here')
                continue
            n += 1
            shape = UE_SHAPE.sub(b'N', text[:240])
            shapes[shape] += 1
            m = R_UE_SRC.match(text)
            prev_src = m.group(1) if m else (b'Lua' if text.startswith(b'[Lua]') else b'UE4SS')
            srcs[prev_src] += 1
            prev_text, prev_shape = text, shape
            mm = R_UE_MOD.match(text)
            if mm:
                mods.append(mm.group(1).decode('utf-8', 'replace'))
            if prev_src != b'AC8SurvivalMode' and UE_ERR.search(text):
                if shape in errs:
                    errs[shape][0] += 1
                else:
                    errs[shape] = [1, last_stamp, text]
        dec = lambda b: b.decode('utf-8', 'replace') if isinstance(b, bytes) else b
        self.ue = {'lines': n, 'bytes': nbytes, 'first': dec(first_stamp), 'last': dec(last_stamp), 'mods': mods,
                   'top': [(dec(s), c) for s, c in shapes.most_common(10)], 'srcs': [(dec(s), c) for s, c in srcs.most_common(8)],
                   'errs': sorted(((v[0], dec(v[1]), dec(v[2])) for v in errs.values()), key=lambda x: -x[0])[:12],
                   'started_over': started_over, 'cap': cap, 'name': src.name}

    def scan_game_logs(self):
        for s in self.b.game_logs:
            for line in s.lines():
                if GAME_ERR.search(line):
                    self.game_errs[(s.name, shape_of(line[line.find(']') + 1:] if line.startswith('[') else line))] += 1

    def settle(self):
        """after the parse: names, own slot, the DOWN / back events in one shape, the runtime's own facts"""
        e = self.ev
        seen = sorted([(x[0], x[1], x[2]) for x in e['player_is']] + [(x[0], x[3], x[1]) for x in e['joined']] +
                      [(x[0], x[1], x[2]) for x in e['rtt']])
        self.occupants = defaultdict(list)
        for t, s, name in seen:                 # (each slot's player as it changes: a name seen there after another)
            occ = self.occupants[s]
            if not occ or occ[-1][1] != name:
                occ.append((t, name))
        for t, s, name in seen:
            self.names.setdefault(s, set()).add(name)
        self.version = self.version or (e['loaded'][0][1] if e['loaded'] else None)
        self.runtime = self.runtime or (e['n_runtime'][0][1] if e['n_runtime'] else None)
        self.hash = self.hash or (e['n_hash'][0][1] if e['n_hash'] else None)
        self.slot = (e['youare'][-1][1] if e['youare'] else None) or (e['streams'][0][1] if e['streams'] else None)
        e['lb'] += [(t, 'native', x) for t, x in e['lb_native']]
        for t, hp, rnd in e['selfdown']:
            e['down'].append((t, 'self', None, 'round %d, %d HP' % (rnd, hp)))
        for t, s, name in e['otherdown']:
            e['down'].append((t, 'other', name, 'player %d' % s))
        for t, why in e['downover']:
            e['runover'].append((t, 'down: ' + why))


def l_revback(g, t, text):
    m = re.match(r'revive: back \(revived by (.*?)\) after (\d+) s down', text)
    if m:
        g.ev['back'].append((t, 'self', None, m.group(1)))


LUA = {'round': Game.l_round, 'hud:': Game.l_hud, 'leaderboard:': Game.l_lb, 'special:': Game.l_special,
       'carrier:': Game.l_zfa, 'dive:': Game.l_zfa, 'escort:': Game.l_zfa, 'allies:': Game.l_zfa, 'perf:': Game.l_perf,
       'revive:': l_revback}


def load_game(path, idx, args, root=None, roots=()):
    b = open_bundle(path, args.session, root=root)
    g = Game(b, idx)
    g.where = os.path.basename(os.path.normpath(path)) + ('' if root is None else '/' + root if root else ' (its top folder)')
    if root is not None:
        b.notes.insert(0, 'the bundle holds the logs of %d games, each read as its own (its folders: %s): this one\'s is %s; '
                          'if they\'re one player\'s, give the one wanted alone' % (len(roots), ', '.join(r or '(top)' for r in
                                                                                         roots[:8]), root or 'the top folder'))
    f = b.files
    jobs = [('native', g.parse_native), ('lua', g.parse_lua), ('crumbs', g.parse_crumbs)]
    if not args.no_ue4ss:
        jobs.append(('ue4ss', g.scan_ue4ss))
    for kind, fn in jobs + [(None, lambda _: g.scan_game_logs())]:
        if kind is None or kind in f:
            try:
                fn(f.get(kind))
            except READ_ERRORS as e:
                b.notes.append('%s could not be read to its end (%s): the page has what came before' % (
                    f[kind].name if kind else 'Saved/Logs', type(e).__name__))
    g.settle()
    g.session = {}
    if 'session' in f:
        for line in f['session'].head(16384).splitlines():
            if '=' in line:
                k, v = line.split('=', 1)
                g.session[k.strip()[:32]] = v.strip()[:200]
    g.version = g.version or g.session.get('mod')
    g.runtime = g.runtime or g.session.get('rt')
    g.hash = g.hash or g.session.get('build_hash')
    g.report = f['report'].head(20000) if 'report' in f else None
    g.bundletxt = f['bundle'].head(20000) if 'bundle' in f else None
    g.stats_txt = f['ue4ss_stats'].head(4096) if 'ue4ss_stats' in f else None
    roles = sorted(g.ev['role'])
    first = next((r for r in roles if r[1] in ('host', 'joiner')), None)
    if first:
        g.role, g.role_why = first[1], first[2]
    elif g.slot and g.slot > 1:
        g.role, g.role_why = 'joiner', 'player %s' % g.slot
    else:
        g.role, g.role_why = ('solo', 'no co-op lines') if not g.ev['sys'] and not g.ev['rtt'] else ('co-op', '')
    t0 = first[0] if first else min([t for t, _ in g.ev['youare']] + [x[0] for x in g.ev['streams']] or [float('-inf')])
    if g.role == 'joiner' and any(r[1].startswith('host') and r[0] > t0 for r in roles):
        g.role_why += '; later the host by migration'
    if g.role == 'host' and not g.slot:
        g.slot = 1
    if g.slot and g.steam:
        g.names.setdefault(g.slot, set()).add(g.steam)
    return g


# ---- rounds -------------------------------------------------------------------------------------------------------
def kind_of(detail, call_sub, strike):
    m = re.search(r'special (\w+):', detail or '')
    if m:
        return 'special', m.group(1)
    if call_sub.startswith('ACE SQUADRONS: '):
        return 'ace', call_sub[15:].title()
    if 'bomber raid' in (detail or ''):
        return 'bomber raid', ''
    if strike:
        return 'strike package', ''
    return 'normal', ''


def build_rounds(g):
    """the rounds: a host's start lines (`round N: X aircraft`), and a joiner's `ROUND N` callouts that announce none
    (a callout announces the next start line when it's the same round's, no host migration between: a joiner that
    became the host has its joiner rounds, then its own)"""
    starts, calls, rows = g.ev['start'], g.ev['call_round'], []
    migs = [x[0] for x in g.ev['migration']] + [x[0] for x in g.ev['role'] if x[1] == 'host (migration)']
    owner = {}
    for ci, (ct, cn, sp, cs) in enumerate(calls):
        j = next((j for j, x in enumerate(starts) if x[0] >= ct - 5), None)
        if j is not None and starts[j][1] == cn and starts[j][0] - ct <= 600 and not any(ct < x <= starts[j][0] for x in migs):
            owner[ci] = j
    for j, (t, n, ac, detail) in enumerate(starts):
        sub = next((calls[ci][3] for ci in sorted(owner, reverse=True) if owner[ci] == j), '')
        strike = any(st == n and abs(t0 - t) < 5 for t0, st in g.ev['strike'])
        k, name = kind_of(detail, sub, strike)
        waves = re.search(r'(\d+) waves', detail)
        rows.append({'t': t, 'n': n, 'aircraft': ac, 'kind': k, 'special': name, 'sub': sub, 'host_style': True,
                     'waves': int(waves.group(1)) if waves else 1, 'detail': detail})
    seen = set()
    for ci, (ct, cn, sp, cs) in enumerate(calls):
        if (cn, int(ct // 60)) in seen or ci in owner:
            continue
        seen.add((cn, int(ct // 60)))
        k = 'special' if sp else ('ace' if cs.startswith('ACE SQUADRONS: ') else 'normal')
        rows.append({'t': ct, 'n': cn, 'aircraft': None, 'kind': k, 'special': cs[15:].title() if k == 'ace' else '',
                     'sub': cs, 'waves': None, 'detail': '', 'host_style': False})
    rows.sort(key=lambda r: r['t'])
    clears = sorted(set((t, n) for t, n in g.ev['clear'] + g.ev['jclear'] + g.ev['call_clear']))
    run = 1
    prev = None
    overs = sorted(g.ev['runover'])
    # (a new run: a run over, a new co-op run, the Lua loaded again; or a round number not above the last, but not
    # after a host migration: there the new host starts the room's round again, the same run)
    ids, marks = [], []
    for t, text in sorted(g.ev['runstart']):
        m = re.match(r'co-op run (\w+)', text)
        if m and (not ids or ids[-1] != m.group(1)):
            marks.append(t)
        ids.append(m.group(1) if m else text)
    marks += [t for t, _ in overs] + [t for t, _ in g.ev['loaded'][1:]]
    for i, r in enumerate(rows):
        nxt = rows[i + 1]['t'] if i + 1 < len(rows) else (g.last or r['t']) + 1
        if prev and (any(prev['t'] < x <= r['t'] for x in marks) or
                     (r['n'] <= prev['n'] and not any(prev['t'] < x <= r['t'] for x in migs))):
            run += 1
        r['run'] = run
        r['clear'] = next((t for t, n in clears if n == r['n'] and r['t'] - 5 <= t <= nxt + 30), None)
        r['end'] = nxt
        ro = next((w for ot, w in overs if r['t'] <= ot <= nxt + 1), None)
        if r['clear'] is not None:
            r['outcome'] = 'cleared'
        elif ro:
            r['outcome'] = ro
        elif any(r['t'] < x <= nxt for x in migs):
            r['outcome'] = 'not cleared (host migration)'
        elif i + 1 == len(rows):
            r['outcome'] = 'not cleared (the log ends)'
        else:
            r['outcome'] = 'not cleared'
        st = next((s for s in g.ev['stats'] if s[1] == r['n'] and r['t'] - 5 <= s[0] <= nxt + 60), None)
        r['players'] = st[4] if st else None
        r['down'] = st[7] if st else None
        r['yours'] = st[8] if st else None
        if r['kind'] == 'normal' and not r['host_style'] and any(r['t'] <= x[0] < nxt for x in g.ev['valka']):
            r['kind'], r['special'] = 'special', 'valka'        # (VALKA's round: a plain ROUND N callout; the host's mood)
        if st and r['kind'] == 'normal' and not r['host_style'] and st[3] not in ('?', 'normal'):
            r['special'] = st[3]
        if r['kind'] == 'special' and not r['special']:
            r['special'] = r['sub'].title()
        prev = r
    g.rounds = rows
    return rows


def round_at(g, t):
    best = None
    for r in g.rounds:
        if r['t'] <= t:
            best = r
        else:
            break
    if best and t > (best['clear'] or best['end']) + 2:
        return None, best
    return best, best


def kind_text(r):
    k = r['kind']
    if k == 'special':
        s = r['special'] or '?'
        return 'special: ' + md(s, 40) + (' (' + md(r['sub'].lower(), 60) + ')' if r['sub'] and r['sub'].lower() != s.lower() else '')
    if k == 'ace':
        return 'ace squadron: ' + md(r['special'], 40)
    return k


# ---- several games: one clock -------------------------------------------------------------------------------------
def clear_pairs(g):
    out = {}
    for t, n in sorted(g.ev['clear'] + g.ev['jclear'] + g.ev['call_clear']):
        lst = out.setdefault(n, [])
        if not lst or t - lst[-1] > 20:
            lst.append(t)
    return out


def align(ref, g):
    a, b = clear_pairs(ref), clear_pairs(g)
    diffs = []
    for n, ts in a.items():
        for tb in b.get(n, ()):
            for ta in ts:
                diffs.append((tb - ta, n))
    if not diffs:
        return None
    diffs.sort()
    best, bi = 0, 0
    j = 0
    for i in range(len(diffs)):
        while diffs[i][0] - diffs[j][0] > 20:
            j += 1
        if i - j + 1 > best:
            best, bi = i - j + 1, j
    members = [d for d in diffs[bi:bi + best]]
    off = statistics.median(d for d, _ in members)
    near = [(d, n) for d, n in diffs if abs(d - off) <= 600]
    odd = sorted(set((n, round(d - off)) for d, n in near if abs(d - off) > 5))
    return {'offset': off, 'matched': len(members), 'spread': members[-1][0] - members[0][0], 'odd': odd}


EXACT = [(R(r'special: rocket ([AB]) escaped'), 'SV_SpRocketEsc%s', 1), (R(r'special: round \d+, the shuttle lifted off'), 'SV_ShuttleLaunched', 1)]


def flag_changes(g):
    """flag -> [(last t read old, first t read new, old, new)]: the round probes' reads, narrowed to the time of a line
    that says when it happened (a rocket's escape, the shuttle's liftoff)"""
    exact = defaultdict(list)
    for key in ('rocket', 'shuttle'):
        for t, text in g.ev[key]:
            for rx, flag, v in EXACT:
                m = rx.match(text)
                if m:
                    exact[(flag % m.group(1)) if '%' in flag else flag].append((t, v))
    out = defaultdict(list)
    last = {}
    for t, flags in g.ev['probe']:
        for k, v in flags.items():
            if k in last and last[k][1] != v:
                a, b = last[k][0], t
                x = next((xt for xt, xv in exact.get(k, ()) if xv == v and a - 2 <= xt <= b + 2), None)
                out[k].append((x, x, last[k][1], v) if x is not None else (a, b, last[k][1], v))
            last[k] = (t, v)
    return out


def disagreements(ref, g):
    notes = []
    al = g.aligned
    if al:
        for n, d in al['odd'][:12]:
            notes.append('round %d cleared %+d s apart (after the offset)' % (n, d))
    lo, hi = g.ref(g.first), g.ref(g.last)
    rs = set((r['run'], r['n']) for r in ref.rounds if lo <= r['t'] <= hi)
    gs = set(r['n'] for r in g.rounds)
    miss = sorted(n for _, n in rs if n not in gs)
    if miss and g.rounds:
        notes.append('rounds the reference started while this game was up but this game shows no start of: %s'
                     % ', '.join(str(n) for n in miss[:20]))
    # DOWN: this game's own downs against the reference's word on that player
    me = callout_name(g.steam)
    if me:
        ref_downs = [t for t, who, name, _ in ref.ev['down'] if callout_name(name) == me or
                     (who == 'self' and callout_name(ref.steam) == me)]
        last = None
        for t, who, _, _ in sorted(g.ev['down']):
            if who != 'self' or (last is not None and t - last < 30):
                continue
            last = t
            tr = g.ref(t)
            near = [x for x in ref_downs if abs(x - tr) <= 60]
            if not near and ref.first is not None and ref.first + 60 <= tr <= ref.last - 60:
                notes.append('%s went down at %s on its own game; the reference shows no %s DOWN within a minute'
                             % (md(g.steam), g.at(t), md(g.steam)))
            elif near and min(abs(x - tr) for x in near) > 10:
                notes.append('%s down at %s here, %d s apart on the reference' % (md(g.steam), g.at(t), round(min(abs(x - tr) for x in near))))
    # the event package's flags (round probes): a change seen at clearly different times
    fa, fb = flag_changes(ref), flag_changes(g)
    told = defaultdict(list)
    span = lambda a, b, at: ('at ' + at(a)) if a == b else 'between %s and %s' % (at(a), at(b))
    for k in sorted(set(fa) & set(fb)):
        for a0, a1, ov, nv in fa[k]:
            for b0, b1, ov2, nv2 in fb[k]:
                b0r, b1r = g.ref(b0), g.ref(b1)
                if (ov, nv) != (ov2, nv2) or abs(b1r - a1) > 600:
                    continue
                if b1r < a0 - 30 or b0r > a1 + 30:
                    told[(ov, nv, span(a0, a1, hms), span(b0, b1, g.at))].append(k)
                break
    for (ov, nv, a, b), ks in sorted(told.items(), key=lambda kv: kv[0][2])[:15]:
        notes.append('%s %d -> %d: %s on the reference, %s here' % (md(', '.join(ks[:6]) + (' +%d more' % (len(ks) - 6) if
                                                                                         len(ks) > 6 else ''), 200), ov, nv, a, b))
    return notes


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
        if g.version and vtuple(g.version) and vtuple(g.version) < CHECKLIST_BUILD:
            p.add('- this build is older than %s: the checklist\'s lines can\'t be in its logs' % '.'.join(map(str, CHECKLIST_BUILD)))
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


def sec_store(p, games, ref):
    p.h(2, 'STORE windows')
    p.add('A window is the music\'s hold (`music: track clock held (landing store)` to `running`; else the runtime\'s '
          '`minigame:` lines). Hard rule 64: a host event fired in it runs none of its records. **Bold**: fired and not '
          'one of the repeating orders, so check it took; (h): the host\'s, forwarded to this game; ~: named as NOT run '
          'here (not fired, dropped, held, didn\'t take); !: a special\'s moment logged inside the window (a liftoff, a '
          'launch: did it take?). Each other game\'s windows also list what the reference\'s log (the host\'s) fired in '
          'them, its clock aligned.')
    bold = lambda k: k.startswith('!') or (not k.startswith('~') and not REPEATING.search(k))
    for g in games:
        p.h(3, md(g.label))
        wins = store_windows(g)
        if not wins:
            p.add('No STORE window.')
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
    p.h(2, 'Checklist: 0.74.52\'s new log lines')
    p.add('From HISTORY.md\'s 0.74.51 and 0.74.52 entries and docs/re (LAG, ZFA44, ESCORT, COOP, ALICORN, SPACEPORT_ASSAULT, '
          'BEHAVIOUR_DIRECTOR). Expect: yes, every run; when, only when it happens; no, a sign of trouble (should stay unseen).')
    for g in games:
        v = vtuple(g.version or '')
        if v and v < CHECKLIST_BUILD:
            p.add('', '%s runs %s, older than 0.74.52: none of these can be there.' % (md(g.label), md(g.version)))
    head = ['Fix', 'Area', 'Log', 'The line', 'Expect'] + [md(g.label, 30) for g in games]
    rows = []
    for i, c in enumerate(CHECKS):
        row = [c[0], c[1], c[2], code(readable(c[3]), 90), c[6]]
        for g in games:
            n = g.checks.get(i, 0)
            row.append(('seen %d (first %s)' % (n, g.at(g.check_first[i]))) if n else 'not seen')
        rows.append(row)
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


def check_anchors():
    srcs = []
    for d, exts in (('mod/UE4SS/AC8SurvivalMode/Scripts', ('.lua',)), ('runtime', ('.c', '.h'))):
        full = os.path.join(ROOT, d)
        for fn in sorted(os.listdir(full)):
            if fn.endswith(exts):
                with open(os.path.join(full, fn), encoding='utf-8', errors='replace') as f:
                    srcs.append(f.read())
    text = '\n'.join(srcs)
    bad = 0
    for c, rx in CHECK_RX:
        if c[4] not in text:
            print('log_report: checklist %s %r: its anchor %r is not in the code any more' % (c[0], c[3], c[4]))
            bad += 1
        if not rx.match(c[5]):
            print('log_report: checklist %s %r does not take its own sample %r' % (c[0], c[3], c[5]))
            bad += 1
    print('log_report: %d checklist lines, %d problems' % (len(CHECKS), bad))
    return 1 if bad else 0


def main(argv=None):
    ap = argparse.ArgumentParser(description='One Markdown page from Survival log bundles (docs/re/LOG_REPORT.md).')
    ap.add_argument('bundles', nargs='*', help='a folder or a .zip each (a host and its joiners: the clocks are aligned)')
    ap.add_argument('-o', '--out', help='write the page here (else it goes to stdout)')
    ap.add_argument('--session', help='the session stamp to read in a folder of several (YYYY-MM-DD_HH-MM-SS)')
    ap.add_argument('--ref', type=int, help='the bundle (1, 2, ...) whose clock the page uses (default: the host)')
    ap.add_argument('--title', help='the page\'s title')
    ap.add_argument('--no-ue4ss', action='store_true', help='skip UE4SS.log (the slowest file)')
    ap.add_argument('--check-anchors', action='store_true', help='check the checklist against the code and stop')
    args = ap.parse_args(argv)
    if args.check_anchors:
        return check_anchors()
    if not args.bundles:
        ap.error('give one or more bundles')
    t0 = time.time()
    games = []
    for path in args.bundles:
        roots = bundle_roots(path)              # (several players' folders in one bundle: a game each)
        for root in roots or [None]:
            games.append(load_game(path, len(games), args, root, roots))
    labels = Counter()
    for g in games:
        base = g.steam or (sorted(g.names[g.slot])[0] if g.slot in g.names else '') \
            or g.where or 'game %d' % (g.idx + 1)
        labels[base] += 1
        g.label = base + (' #%d' % labels[base] if labels[base] > 1 else '') + ' (%s)' % (g.role or '?')
        build_rounds(g)
    if args.ref:
        if not 1 <= args.ref <= len(games):
            ap.error('--ref takes 1 to %d' % len(games))
        ref = games[args.ref - 1]
    else:
        ref = next((g for g in games if g.role == 'host'), games[0])
    for g in games:
        if g is not ref:
            g.aligned = align(ref, g)
            g.offset = g.aligned['offset'] if g.aligned else 0.0
    page = report(games, ref, args.title)
    for g in games:
        g.b.close()
    if args.out:
        with open(args.out, 'w', encoding='utf-8', newline='\n') as f:
            f.write(page)
        print('log_report: %s written (%d lines, %.1f s)' % (args.out, page.count('\n'), time.time() - t0))
    else:
        sys.stdout.write(page)
    return 0


if __name__ == '__main__':
    sys.exit(main())
