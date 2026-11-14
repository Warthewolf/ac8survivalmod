"""lua_split_part.py : splits one of the runtime's parts (Scripts/sv_<x>.lua) into a family of parts that main.lua runs
one after the other (a contributor, 2026-11-07: "some files have too much line of code, almost 6k for sv_coop.lua and
many over 2k, not maintainable for human or AI"). tools/lua_split.py's way, for a part instead of the old main.lua.

  python -I tools/lua_split_part.py <part>             analyse only: the plan, what each piece shares, any problem
  python -I tools/lua_split_part.py <part> --write     write the pieces and add them to main.lua's MODULES
  python -I tools/lua_split_part.py <part> --list [N]  the part's statements of N lines or more (where it can be cut)

<part> is a PLANS key. The first piece keeps the part's name, the others are <part>_<topic>.lua, run by main.lua right
after it in PLANS' order (tools/lua_parts.py and tools/checks/parts.lua read a part's family from MODULES).
A part that is itself a piece of a family (PLANS 'family': sv_config_specials.lua, sv_config.lua's) is split the same
way: its new pieces are that family's, <family>_<topic>.lua, run right after it, and each one's header counts the whole
family; the part's own header, and the other pieces' headers counting the family, are brought up to date by hand.

How the split keeps the behaviour. The part was one chunk run top to bottom; its pieces are consecutive slices of it,
run in the same order in the same Lua state (main.lua: io + load, as every part). A cut falls:
  - between two top-level statements (as lua_split.py's);
  - between two statements of a top-level `do ... end` (sv_coop.lua and sv_anomalies.lua are one each, kept for hard
    rule 23's 200 locals): the piece before it gets an `end`, the piece after it a `do`;
  - between two fields of a top-level table constructor (sv_config.lua's `CFG = {`, one statement of 2,755 lines;
    or a field of a global table's, a dotted name: sv_config_specials.lua's `CFG.specials = {`, 1,551 lines):
    the constructor is closed there and each field from the cut on becomes a statement `CFG.<key> = <value>` (or
    `CFG.specials.<key> = <value>`) of the next piece, in the same order (a field written as a block, `key = {` alone
    on its line, one indent less; one whose value goes on from its key's line keeps its lines as they are, `CFG.` in
    place of its indent). The table gets the same keys and values in the same order. Only its internal layout can
    differ (built in steps, not presized), so the order pairs() walks it: Lua leaves that order unspecified (and 5.4
    seeds its string hashes per Lua state anyway). A moved value is now evaluated after the table is assigned, not
    before: the analysis fails on one that reads the table's (first) name outside a function, and lists the globals
    they read as they're built.
A local of the part's main chunk or of its top-level do block (a "unit" local) that another piece uses becomes a global
of the state: its statement's `local ` is dropped (a bare `local a, b` becomes `a, b = nil, nil`), nothing else changes.
Every name still means the declaration it meant (the analysis resolves them by scope with lua_check.py's parser): it
refuses a name that would turn global while any part (this one included) already reads or sets a global of that name or
looks it up in _G, one declared twice whose two declarations would both turn global, a Lua / UE4SS global's name, an
SV_* (the runtime's natives), a statement sharing its line with another, a TEST ONLY / DEV ONLY / ONLINE ONLY block cut in two and
a moved field it can't shift exactly. The pieces, with `local` put back, the moved fields' lines as they were and the
added lines (headers, `end` / `do`, `}`) taken out, are byte for byte the old file (checked before writing; CRLF kept).
"""
import os, re, sys, glob
HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
sys.path.insert(0, os.path.join(HERE, 'checks'))
from lua_split import Resolver, BARE
from lua_check import tokenize, KNOWN_GLOBALS

SCRIPTS = os.path.join(HERE, '..', 'mod', 'UE4SS', 'AC8SurvivalMode', 'Scripts')
MAIN = os.path.join(SCRIPTS, 'main.lua')
CHECKS = os.path.join(HERE, 'checks')
INDENT = '    '

# PLANS[part]['pieces'] = [(piece, cut, what it holds)]: the first piece is the part itself (cut None, what None: its
# own header stays, a line naming the family before it); a cut is ('at', text): at the first statement that starts at
# or after the one line beginning with `text`, snapped back to where that statement's comments begin, or ('fields',
# table, key): the top-level `table = {` constructor's fields from `key` on.
# A part that is a piece of a family already: 'family': the family's first part (its new pieces <family>_<topic>).
# A field cut's table may be a dotted name ('CFG.specials': `CFG.specials = {`, its fields from `key` on).
# A shared unit local that can't turn global (its name is another part's global, or it holds a global's value taken
# as the part loads) is handed on instead, never turned global:
#   'carry': {name: table}: a local that is never assigned again (`local M = { ... }`); the piece declaring it adds
#            `table.name = name` right after it, each later piece using it starts with `local name = table.name`
#            (table: a global table of the part's own, which no part has that field of);
#   'redeclare': [name]: a local whose statement reads only globals the part never sets (`local crumb = crumb or
#            function() end`); each later piece using it starts with the same statement.
BANNER = '-' * 100 + ' '
PLANS = {
    'sv_coop': {'carry': {'M': 'COOP'}, 'redeclare': ['crumb'], 'pieces': [
        ('sv_coop', None, None),
        ('sv_coop_joiner', ('at', BANNER + 'joiner'),
         "Survival COOP, a joiner's side: the host's flights here, copied, bound to their streams and kept up"),
        ('sv_coop_planes', ('at', BANNER + "the other players' planes"),
         "Survival COOP, the players' planes: the stand-ins and the real planes, modded planes and skins, what's sent "
         "of yours, a rejoin in another aircraft, the players for the other parts"),
        ('sv_coop_sync', ('at', BANNER + 'weapons, gear, afterburner'),
         "Survival COOP, what's synced: weapons, gear and afterburners, the messages, the allies and defences"),
        ('sv_coop_migration', ('at', BANNER + 'host migration'),
         "Survival COOP, host migration, the rest of the runtime wrapped for co-op, and the co-op tick"),
    ]},
    'sv_config': {'pieces': [
        ('sv_config', None, None),
        ('sv_config_specials', ('fields', 'CFG', 'specials'),
         "CFG's last settings, each a statement of its own from `CFG = {` (sv_config.lua): CFG.specials (every "
         "special round's), CFG.sky (the sky and the day-night arc), CFG.music and CFG.hud (the HUD and its texts)"),
        ('sv_config_ini', ('at', 'for n = 1, 8 do for k = 0, 2 do CFG.pool'),
         "the shipped settings (CFG_DEFAULTS), survival.ini and survival_config.lua over them, the difficulty preset, "
         "and what's built on CFG: the behaviour probe's tables, ACE, TIER, ROLE and the game's own Lua (GLS)"),
    ]},
    'sv_anomalies': {'pieces': [
        ('sv_anomalies', None, None),
        ('sv_anomalies_valka', ('at', '-- her components of class `cls`'),
         "VALKA's X-02S, paint, opener railgun and round (her blinks, railgun rounds, flares, sounds and parts are "
         "sv_anomalies.lua's); the special kinds table (SPC.kinds); PHANTASM's pack and the Anomaly's tick; a co-op "
         "joiner's field and copy of AB.L..IN"),
        # (named and described without what it holds: a release keeps this header, and thunder_test.sh finds no trace
        # of the test-only special in a release's parts)
        ('sv_anomalies_dev', ('at', '-- TEST ONLY BEGIN (the lightning Anomaly'),
         "the specials' code for test builds only: the whole piece is one test-only block, which "
         "tools/strip_test_only.py takes out of a release (only this header is left there)"),
    ]},
    # ((2026-11-12) sv_tanicorn.lua at 1,980 of 2,000 lines before stage 4's railguns: the rise in a piece of its own; both
    # pieces dev-only blocks whole (the user's dev install and a TESTER=1 TANI=1 zip: tools/dev_only.py))
    'sv_tanicorn': {'pieces': [
        ('sv_tanicorn', None, None),
        ('sv_tanicorn_rise', ('at', '-- (2026-11-11) Ctrl+R: THE TANACORN rises on her rig'),
         "THE TANACORN's rise (Ctrl+R): its rig, its water and sound, the cinematic and its camera; the dev install's "
         "test code only: a release keeps this header alone"),
    ]},
    # (2026-11-11, both at 1,985-1,997 lines: each piece with room under the 2,000-line limit)
    'sv_escort': {'pieces': [
        ('sv_escort', None, None),
        ('sv_escort_carriers', ('at', BANNER + 'the carriers'),
         "the ZFA-44 carriers (CFG.allies.carrier, the STORE's ZfaCarrier): the STORE's row, a carrier sent, each "
         "ship's launches and service, a ship sunk or leaving, a joiner's own ZFA-44s; co-op's \"es\" (THE ESCORT's "
         "state and the carriers' for the joiners); then every tick's, THE ESCORT's and the carriers': the names on "
         "the boxes, the main menu's rows, ESC.tick, a restart and a level torn down"),
    ]},
    # (a piece of sv_config.lua's family: its new piece sv_config_<topic>, run right after it, before sv_config_subs;
    # named and described without the test-only special it holds too: a release keeps this header, and
    # thunder_test.sh finds no trace of that special in a release's parts)
    'sv_config_specials': {'family': 'sv_config', 'pieces': [
        ('sv_config_specials', None, None),
        ('sv_config_arc', ('fields', 'CFG.specials', 'fishing'),
         "CFG.specials' last fields, each a statement of its own from `CFG.specials = {` (sv_config_specials.lua): "
         "GONE FISHIN' and THE FESTIVAL (CFG.specials.fishing, festival and the rest); CFG.sky (the sky and the "
         "day-night arc), CFG.music and CFG.hud (the HUD and its texts)"),
    ]},
}


def norm(path):
    """the file's text with LF line ends, and its line end (CRLF or LF) to write back"""
    raw = open(path, 'rb').read().decode('utf-8')
    eol = '\r\n' if '\r\n' in raw else '\n'
    text = raw.replace('\r\n', '\n')
    assert '\r' not in text, f'{path}: a lone CR'
    return text, eol


class Units(Resolver):
    """lua_split.py's Resolver, its top-level statements widened to units: the main chunk's statements and those
    directly inside a top-level do block. Also records the do blocks and one table constructor's fields."""
    def __init__(self, toks, table_name=None):
        super().__init__(toks)
        self.units = []       # [start line, end line, [decl indexes], do block index or None]
        self.dos = []         # [do line, end line]
        self.in_do, self.cur_do, self.cur_unit = False, None, None
        self.table_name = table_name
        self.table_path = table_name.split('.') if table_name else None   # (a dotted name: `CFG.specials = {`)
        self.ctor = None      # {'open', 'close': lines, 'fields': [[key, first line, last line, separator line]]}
        self.uses = []        # (decl index or None, name, line, function depth)

    def unit_level(self):
        return self.depth_fn == 0 and (len(self.scopes) == 2 or (len(self.scopes) == 3 and self.in_do))

    def declare(self, n, line=None):
        unit = self.cur_unit if self.unit_level() else None
        self.decls.append((n, line if line is not None else self.peek()[2], unit))
        self.scopes[-1][n] = len(self.decls) - 1
        if unit is not None: self.units[unit][2].append(len(self.decls) - 1)

    def use(self, n, line):
        d = self.resolve(n)
        self.refs.append((d, n, line))
        self.uses.append((d, n, line, self.depth_fn))

    def block(self):
        self.scopes.append({})
        unit = self.unit_level()
        while not self.block_follow():
            if self.check('return'):
                self.k += 1
                if not self.block_follow() and not self.check(';'): self.explist()
                self.accept(';'); break
            idx = None
            if unit:
                self.units.append([self.peek()[2], None, [], self.cur_do if len(self.scopes) == 3 else None])
                idx = self.cur_unit = len(self.units) - 1
            self.statement()
            if idx is not None: self.units[idx][1] = self.t[self.k - 1][2]
        self.scopes.pop()

    def statement(self):
        top = self.depth_fn == 0 and len(self.scopes) == 2
        if top and self.check('do'):
            self.k += 1
            self.dos.append([self.t[self.k - 1][2], None]); d = len(self.dos) - 1
            self.in_do, self.cur_do = True, d
            self.block()
            self.dos[d][1] = self.peek()[2]
            self.expect('end')
            self.in_do, self.cur_do = False, None
            return
        if top and self.table_name and self.at_table():
            assert self.ctor is None, f'{self.table_name}: two top-level `{self.table_name} = {{`'
            self.use(self.table_path[0], self.peek()[2]); self.k += 2 * len(self.table_path)
            self.ctor = self.record_table()
            return
        super().statement()

    def at_table(self):
        """the statement here is `<table_name> = {` (a dotted name's names and dots, then `=` and `{`)"""
        i = 0
        for j, n in enumerate(self.table_path):
            if j and not (self.peek(i)[0] == 'op' and self.peek(i)[1] == '.'): return False
            i += 1 if j else 0
            if not (self.peek(i)[0] == 'name' and self.peek(i)[1] == n): return False
            i += 1
        return self.peek(i)[1] == '=' and self.peek(i + 1)[1] == '{'

    def record_table(self):
        open_ = self.peek()[2]
        self.expect('{')
        fields = []
        while not self.check('}'):
            first, key = self.peek()[2], None
            if self.check('['): self.k += 1; self.expr(); self.expect(']'); self.expect('='); self.expr()
            elif self.peek()[0] == 'name' and self.peek(1)[1] == '=' and self.peek(1)[0] == 'op':
                key = self.peek()[1]; self.k += 2; self.expr()
            else: self.expr()
            last, sep = self.t[self.k - 1][2], None
            if self.check(',') or self.check(';'): sep = self.peek()[2]; self.k += 1
            fields.append([key, first, last, sep])
            if sep is None: break
        close = self.peek()[2]
        self.expect('}')
        return {'open': open_, 'close': close, 'fields': fields}


def unit_decls_of(p, n):
    return [d for d, (m, l, u) in enumerate(p.decls) if m == n and u is not None]


def parse(text, table_name=None):
    p = Units(tokenize(text), table_name)
    p.block()
    assert p.peek()[0] == 'eof'
    return p


def free_names(path):
    """every name a Lua file reads or sets as a global (a use no local declaration covers)"""
    text, _ = norm(path)
    p = Resolver(tokenize(text))
    p.block()
    return {n for d, n, _ in p.refs if d is None}


def modules():
    src, _ = norm(MAIN)
    body = src[src.index('local MODULES = {'):]
    body = body[:body.index('\n}')]
    return re.findall(r'^\s*"(\w+)",', body, re.M)


def family_of(first):
    """a family's pieces in MODULES' order: its first part, then the MODULES right after it named <first>_<topic>"""
    mods = modules()
    if first not in mods: return [first]
    i, out = mods.index(first) + 1, [first]
    while i < len(mods) and mods[i].startswith(first + '_'):
        out.append(mods[i]); i += 1
    return out


def new_family(part, names):
    """(a piece of a family split again) the family's pieces once the new ones are in, right after the part"""
    fam = family_of(PLANS[part]['family'])
    i = fam.index(part) + 1
    return fam[:i] + names[1:] + fam[i:]


def anchor_line(lines, text):
    hits = [i + 1 for i, l in enumerate(lines) if l.startswith(text)]
    assert len(hits) == 1, f'the cut {text!r}: {len(hits)} lines begin with it (one wanted)'
    return hits[0]


def leads(p):
    """where each unit's lead-in (its comments, blank lines) begins: after the unit before it in its block, or after
    its do block's `do` line, or at line 1"""
    out, last = [], {}
    for u in p.units:
        c = u[3]
        if c in last: out.append(last[c] + 1)
        elif c is not None: out.append(p.dos[c][0] + 1)
        else: out.append(1)
        last[c] = u[1]
    return out


def plan_cuts(part, p, lines):
    """[(piece, kind, first line, what)]: kind ('top',), ('do', its do block) or ('fields', the first moved field)"""
    plan = PLANS[part]['pieces']
    lead = leads(p)
    cuts = [(plan[0][0], ('top',), 1, None)]
    for piece, cut, what in plan[1:]:
        if cut[0] == 'at':
            at = anchor_line(lines, cut[1])
            i = next(i for i, u in enumerate(p.units) if u[0] >= at)
            u = p.units[i]
            if u[3] is not None and lead[i] == p.dos[u[3]][0] + 1:
                sys.exit(f'{piece}: its cut is its do block\'s first statement: cut before the do block instead')
            cuts.append((piece, ('do', u[3]) if u[3] is not None else ('top',), lead[i], what))
        else:
            _, name, key = cut
            assert p.ctor, f'{piece}: no top-level {name} = {{ ... }}'
            fs = [i for i, f in enumerate(p.ctor['fields']) if f[0] == key]
            assert len(fs) == 1 and fs[0] > 0, f'{piece}: {name}.{key}: {len(fs)} fields, or the first'
            prev = p.ctor['fields'][fs[0] - 1]
            cuts.append((piece, ('fields', fs[0]), (prev[3] or prev[2]) + 1, what))
    firsts = [c[2] for c in cuts]
    assert firsts == sorted(firsts) and len(set(firsts)) == len(firsts), f'the cuts are out of order: {firsts}'
    return cuts


def globalise_line(line):
    """a shared unit local's statement as a global's: `local x = v` -> `x = v`; a bare `local a, b  -- why` ->
    `a, b = nil, nil  -- why` (a statement Lua accepts; a new global is nil anyway). Its indent kept."""
    ind = re.match(r'^(\s*)', line).group(1)
    rest = line[len(ind):]
    m = BARE.match(rest)
    if m:
        names = [n.strip() for n in m.group(1).split(',')]
        return f"{ind}{m.group(1)} = {', '.join(['nil'] * len(names))}{m.group(2)}", 'bare'
    assert rest.startswith('local '), line
    return ind + rest[len('local '):], 'prefix'


def localise_line(line, how):
    ind = re.match(r'^(\s*)', line).group(1)
    rest = line[len(ind):]
    if how == 'bare':
        m = re.match(r'^([A-Za-z_]\w*(?:, *[A-Za-z_]\w*)*) = (nil(?:, nil)*)( *(?:--.*)?)$', rest)
        assert m and len(m.group(1).split(',')) == len(m.group(2).split(',')), line
        return f'{ind}local {m.group(1)}{m.group(3)}'
    return ind + 'local ' + rest


def apply(t, steps):
    for s in steps:
        if s[0] == 'dedent': t = t[len(INDENT):]
        elif s[0] == 'key': t = s[1] + t[len(INDENT):]
        elif s[0] == 'decomma': t = t[:-1]
        elif s[0] == 'unlocal': t = globalise_line(t)[0]
    return t


def undo(t, steps):
    for s in reversed(steps):
        if s[0] == 'dedent': t = INDENT + t
        elif s[0] == 'key': t = INDENT + t[len(s[1]):] if t.startswith(s[1]) else '\0'
        elif s[0] == 'decomma': t = t + ','
        elif s[0] == 'unlocal': t = localise_line(t, s[1])
    return t


DO_LINE = 'do  -- ({parent}.lua\'s do block, continued: this piece\'s own helpers stay local to it)'
END_LINE = 'end  -- ({part}.lua\'s do block goes on in {next}.lua)'
CLOSE_LINE = '}}  -- ({table} goes on in {next}.lua: its fields from {key} on)'
PARENT_NOTE = ('-- ({part}.lua is the first of {n} pieces, split by tools/lua_split_part.py: {rest} go on from where it ends,'
               ' run by main.lua right after it, in that order.)')


def split(part):
    """(pieces, out, problems, notes, report): out[k] = the piece's lines [(text, original line or None, steps)]"""
    path = os.path.join(SCRIPTS, part + '.lua')
    text, eol = norm(path)
    fam = PLANS[part].get('family')
    if fam is None and 'tools/lua_split_part.py' in text[:800]:
        sys.exit(f'{part}.lua was split already (its first line names its pieces); PLANS[{part!r}] is the record of how')
    if fam is not None:
        new = [pc[0] for pc in PLANS[part]['pieces'][1:]]
        if any(n in modules() for n in new):
            sys.exit(f'{part}.lua was split already (main.lua MODULES has {new}); PLANS[{part!r}] is the record of how')
        assert part in family_of(fam), f'{part}: not a piece of {fam}.lua\'s family in main.lua MODULES'
        assert all(n.startswith(fam + '_') for n in new), f'{part}: its new pieces are named {fam}_<topic>'
    lines = text.split('\n')
    if text.endswith('\n'): lines = lines[:-1]
    N = len(lines)
    plan = PLANS[part]['pieces']
    table_name = next((c[1] for _, c, _ in plan[1:] if c and c[0] == 'fields'), None)
    p = parse(text, table_name)
    pieces = plan_cuts(part, p, lines)
    names = [pc[0] for pc in pieces]
    problems, notes = [], []
    bounds = [pc[2] for pc in pieces] + [N + 1]
    line_piece = {ln: k for k in range(len(pieces)) for ln in range(bounds[k], bounds[k + 1])}

    # the table cut: each line from the first moved field's lead-in to the constructor's close, and how it changes
    moved, tk = {}, next((k for k, pc in enumerate(pieces) if pc[1][0] == 'fields'), None)
    if tk is not None:
        fi = pieces[tk][1][1]
        fields, close = p.ctor['fields'], p.ctor['close']
        if bounds[tk + 1] <= close: problems.append(f'{names[tk + 1]}: its cut falls inside {table_name}\'s moved fields')
        if lines[close - 1] != '}': problems.append(f'line {close}: {table_name}\'s constructor must close on a line "}}" alone')
        for j in range(fi, len(fields)):
            key, first, last, sep = fields[j]
            if not key: problems.append(f'line {first}: a moved field of {table_name} without a name key'); continue
            lead0 = (fields[j - 1][3] or fields[j - 1][2]) + 1
            end = sep if sep is not None else last
            if sep is not None and sep != last: problems.append(f'{table_name}.{key}: its comma isn\'t on its last line')
            block_style = re.match(r'^' + INDENT + key + r'\s*=\s*\{\s*(--.*)?$', lines[first - 1]) is not None
            for ln in range(lead0, end + 1):
                t, steps = lines[ln - 1], []
                if ln == first:
                    if not t.startswith(INDENT + key): problems.append(f'line {ln}: {table_name}.{key} not one indent in')
                    steps.append(('key', table_name + '.'))
                elif (ln < first or block_style) and t.strip():
                    if not t.startswith(INDENT): problems.append(f'line {ln}: a line of {table_name}.{key} not indented')
                    steps.append(('dedent',))
                if ln == end and sep is not None:
                    if not t.endswith(','): problems.append(f'line {ln}: {table_name}.{key} doesn\'t end in its comma')
                    steps.append(('decomma',))
                moved[ln] = steps
        for ln in range((fields[-1][3] or fields[-1][2]) + 1, close):       # (comments after the last field)
            t = lines[ln - 1]
            if t.strip() and not t.startswith(INDENT): problems.append(f'line {ln}: not indented')
            moved[ln] = [('dedent',)] if t.strip() else []
        # a string over several lines whose lines would shift
        for t in tokenize(text):
            if t[0] == 'string' and '\n' in t[1]:
                for ln in range(t[2] + 1, t[2] + t[1].count('\n') + 1):
                    if ('dedent',) in moved.get(ln, []): problems.append(f'line {t[2]}: a string over several lines would shift')
        # the moved values: none may read the table's own name as they're built
        f0 = fields[fi][1]
        for d, n, ln, depth in p.uses:
            if f0 <= ln < close and depth == 0:
                if n == table_name.split('.')[0]:
                    problems.append(f'line {ln}: a moved field reads {n} as it is built (now after {table_name} is set)')
                elif d is None and n not in KNOWN_GLOBALS: notes.append(f'line {ln}: a moved field reads {n} as it is built')

    # the shared unit locals: a unit's local another piece uses
    decl_piece = {d: line_piece[p.units[u][0]] for d, (n, l, u) in enumerate(p.decls) if u is not None}
    users = {}
    for d, n, ln in p.refs:
        if d in decl_piece: users.setdefault(d, set()).add(line_piece[ln])
    shared = {d for d in decl_piece if users.get(d, set()) - {decl_piece[d]}}
    # the locals handed on instead (PLANS carry / redeclare): never turned global; each later piece using one gets it
    carry, redeclare = PLANS[part].get('carry', {}), PLANS[part].get('redeclare', [])
    handed = {}                                    # decl -> ('carry', table) / ('redeclare', its statement's text)
    for d in sorted(shared):
        n, l, u = p.decls[d]
        if n not in carry and n not in redeclare: continue
        unit = p.units[u]
        if len(unit[2]) != 1: problems.append(f'{n} (handed on): its statement declares other names too')
        if len([e for e in unit_decls_of(p, n) if e in shared]) != 1:
            problems.append(f'{n} (handed on): declared more than once and shared')
        # never assigned again: no `n =` / `n, x =` statement but its own declaration, in this part
        for ln, t in enumerate(lines, 1):
            if ln != unit[0] and re.match(r'^\s*(?:[\w.]+\s*,\s*)*' + n + r'\s*(?:,\s*[\w.]+\s*)*=(?!=)', t):
                problems.append(f'{n} (handed on): assigned again at line {ln}')
        if n in carry:
            tbl = carry[n]
            if any(re.search(r'\b' + tbl + r'\s*\.\s*' + n + r'\b', s) for s in
                   (norm(f)[0] for f in glob.glob(os.path.join(SCRIPTS, '*.lua')))):
                problems.append(f'{n} (handed on): some part has {tbl}.{n} already')
            if not any(dn == tbl and dd is None for dd, dn, _ in p.refs):
                problems.append(f'{n} (handed on): {part}.lua never sets its global {tbl}')
            handed[d] = ('carry', tbl)
        else:
            if unit[1] != unit[0]: problems.append(f'{n} (redeclared): its statement is more than one line')
            for g in {dn for dd, dn, ln in p.refs if dd is None and ln == unit[0]}:     # (the globals it reads)
                for ln, t in enumerate(lines, 1):
                    if re.match(r'^\s*(?:function\s+' + g + r'\b|(?:[\w.]+\s*,\s*)*' + g + r'\s*(?:,\s*[\w.]+\s*)*=(?!=))', t):
                        problems.append(f'{n} (redeclared): {part}.lua sets the global {g} its statement reads (line {ln})')
            handed[d] = ('redeclare', lines[unit[0] - 1])
    shared -= set(handed)
    shared_units = sorted({p.decls[d][2] for d in shared})
    turned = {}
    for u in shared_units:
        for d in p.units[u][2]: turned.setdefault(p.decls[d][0], []).append(d)
    for u in shared_units:
        ln = p.units[u][0]
        if not re.match(r'^\s*local ', lines[ln - 1]):
            problems.append(f'line {ln}: a shared local not at the start of its line: {lines[ln - 1][:70]}')
        if any(v is not p.units[u] and (v[0] == ln or v[1] == ln) and v[3] == p.units[u][3] for v in p.units):
            problems.append(f'line {ln}: a shared local\'s statement shares its line with another statement')
    # the names that turn global must mean nothing else anywhere
    unit_decls = {}
    for d, (n, l, u) in enumerate(p.decls):
        if u is not None: unit_decls.setdefault(n, []).append(d)
    own_free = {}
    for d, n, ln in p.refs:
        if d is None: own_free.setdefault(n, []).append(ln)
    others = {}
    for f in sorted(glob.glob(os.path.join(SCRIPTS, '*.lua'))):
        if os.path.basename(f) == part + '.lua': continue
        for n in free_names(f): others.setdefault(n, []).append(os.path.basename(f))
    texts = {os.path.basename(f): norm(f)[0] for f in glob.glob(os.path.join(SCRIPTS, '*.lua'))}
    tests = {}
    for f in sorted(glob.glob(os.path.join(CHECKS, '*.lua'))):
        try:
            for n in free_names(f): tests.setdefault(n, []).append(os.path.basename(f))
        except Exception as e:
            notes.append(f'(not parsed: {os.path.basename(f)}: {e})')
    for n, ds in sorted(turned.items()):
        if len([d for d in unit_decls[n] if p.decls[d][2] in shared_units]) > 1:
            problems.append(f'{n}: declared {len(unit_decls[n])} times, more than one of them shared (lines '
                            f'{", ".join(str(p.decls[d][1]) for d in unit_decls[n])}): rename one')
        if n in KNOWN_GLOBALS or n.startswith('SV_') or n in ('_ENV', '_G', 'self', 'arg'):
            problems.append(f'{n}: a shared local named like a Lua / UE4SS global or a native')
        if n in own_free:
            problems.append(f'{n}: {part}.lua also reads or sets a global {n} (lines {own_free[n][:8]})')
        if n in others:
            problems.append(f'{n}: a global of {", ".join(others[n])}')
        dyn = [f for f, s in texts.items() if re.search(r'_G\s*\.\s*' + n + r'\b|_G\s*\[\s*["\']' + n + r'["\']', s)]
        if dyn: problems.append(f'{n}: looked up by name in _G in {", ".join(dyn)}')
        if n in tests: notes.append(f'{n} (turns global) is a global of {", ".join(tests[n])}')
    # TEST ONLY / ONLINE ONLY blocks whole in each piece
    for k in range(len(pieces)):
        body = '\n'.join(lines[bounds[k] - 1:bounds[k + 1] - 1])
        for a, b in (('ONLINE ONLY BEGIN', 'ONLINE ONLY END'), ('TEST ONLY BEGIN', 'TEST ONLY END'), ('DEV ONLY BEGIN', 'DEV ONLY END')):
            if body.count(a) != body.count(b): problems.append(f'{names[k]}: {a} / {b} unbalanced (a cut inside one)')

    # the pieces' lines
    drop = {p.units[u][0] for u in shared_units}
    out = [[] for _ in pieces]
    hand_after = {}                                # line -> the hand-over lines after it (carry)
    for d, (how, x) in handed.items():
        n, l, u = p.decls[d]
        if how == 'carry':
            hand_after.setdefault(p.units[u][1], []).append(
                f'{x}.{n} = {n}' + ' ' * max(1, 51 - len(f'{x}.{n} = {n}')) +
                f'-- ({n}, handed to {part}.lua\'s later pieces: tools/lua_split_part.py)')
    for k in range(len(pieces)):
        if pieces[k][1][0] == 'do': out[k].append((DO_LINE.format(parent=part), None, None))
        for d, (how, x) in sorted(handed.items()):
            n, l, u = p.decls[d]
            if k in users.get(d, set()) and k > decl_piece[d]:
                if how == 'carry':
                    t = f'local {n} = {x}.{n}'
                    out[k].append((t + ' ' * max(1, 51 - len(t)) + f'-- ({part}.lua\'s {n}, handed on)', None, None))
                else:
                    out[k].append((x + f'  -- (as in {part}.lua)', None, None))
        if k == tk:
            out[k] += [(apply(lines[ln - 1], st), ln, st) for ln, st in sorted(moved.items())]
        for ln in range(bounds[k], bounds[k + 1]):
            if ln in moved or (tk is not None and ln == p.ctor['close']): continue
            steps = [('unlocal', globalise_line(lines[ln - 1])[1])] if ln in drop else []
            out[k].append((apply(lines[ln - 1], steps), ln, steps))
            for t in hand_after.get(ln, []): out[k].append((t, None, None))
        if k + 1 < len(pieces) and pieces[k + 1][1][0] == 'do':
            out[k].append((END_LINE.format(part=part, next=names[k + 1]), None, None))
        if tk is not None and k + 1 == tk:
            out[k].append((CLOSE_LINE.format(table=table_name, next=names[tk], key=p.ctor['fields'][pieces[tk][1][1]][0]), None, None))
    # the rebuild: every line of the old file once, in order, back to its text
    seen = [ln for k in range(len(pieces)) for _, ln, _ in out[k] if ln is not None]
    for k in range(len(pieces)):
        for t, ln, steps in out[k]:
            if ln is not None and undo(t, steps) != lines[ln - 1]:
                problems.append(f'line {ln}: does not rebuild: {lines[ln - 1][:50]!r} -> {t[:50]!r}')
    omitted = [p.ctor['close']] if tk is not None else []
    if seen != sorted(seen) or sorted(seen + omitted) != list(range(1, N + 1)):
        problems.append('the pieces do not hold every line of the part once, in order')
    report = []
    for k, (piece, kind, first, what) in enumerate(pieces):
        n_sh = sum(1 for d in shared if decl_piece[d] == k)
        n_loc = sum(1 for d in decl_piece if decl_piece[d] == k) - n_sh
        n_lines = len(out[k]) + len(header(part, names, k, what))
        report.append(f'{piece + ".lua":24s} from line {first:5d} ({kind[0]:6s}) {n_lines:5d} lines:'
                      f' shares {n_sh:3d}, keeps {n_loc:3d} local')
    report.append(f'{len(shared)} of {len(decl_piece)} unit locals shared between the pieces; {len(shared_units)} '
                  f'statements lose `local `: {", ".join(sorted(turned))}')
    return pieces, out, problems, notes, report, eol


def build(part, write=False):
    pieces, out, problems, notes, report, eol = split(part)
    for r in report: print(r)
    for nt in notes: print('note:', nt)
    for pr in problems: print('PROBLEM:', pr)
    if problems: sys.exit(1)
    if not write: return
    names = [pc[0] for pc in pieces]
    for k, (piece, kind, first, what) in enumerate(pieces):
        with open(os.path.join(SCRIPTS, piece + '.lua'), 'w', encoding='utf-8', newline='') as f:
            f.write(eol.join(header(part, names, k, what) + [t for t, _, _ in out[k]]) + eol)
    add_modules(part, names[1:])
    print(f'wrote {", ".join(n + ".lua" for n in names)}; main.lua MODULES: {", ".join(names[1:])} after {part}')
    if PLANS[part].get('family'):
        print(f'(by hand now: {part}.lua\'s own header, and the headers of {PLANS[part]["family"]}.lua\'s family that '
              f'count its pieces: {", ".join(n + ".lua" for n in new_family(part, names) if n not in names[1:])})')


def header(part, names, k, what):
    """a piece's first lines: the part's own header stays, a line before it names the family; a new piece says what
    it holds and where it comes from (comment lines of at most 120 characters, as the parts'). A piece of a family
    split again: its own header stays as it is (none added), a new piece counts the whole family."""
    import textwrap
    fam = PLANS[part].get('family')
    if fam is not None:
        if k == 0: return []
        nf = new_family(part, names)
        s = (f'{names[k]}.lua: {what}. Piece {nf.index(names[k]) + 1} of {len(nf)} of {fam}.lua\'s family '
             f'({", ".join(n + ".lua" for n in nf)}), split from {part}.lua by tools/lua_split_part.py and run by main.lua '
             f'right after the piece before it: a name another part uses is a global of this mod\'s Lua state, its own '
             f'helpers stay local.')
        return ['-- ' + l for l in textwrap.wrap(s, 117, break_long_words=False, break_on_hyphens=False)]
    if k == 0:
        s = (f'({part}.lua is the first of {len(names)} pieces, split by tools/lua_split_part.py: '
             f'{", ".join(n + ".lua" for n in names[1:])} {"goes" if len(names) == 2 else "go"} on from where it ends, '
             f'run by main.lua right after it, in that order.)')
    else:
        s = (f'{names[k]}.lua: {what}. Piece {k + 1} of {len(names)} of {part}.lua ({", ".join(n + ".lua" for n in names)}), '
             f'split by tools/lua_split_part.py and run by main.lua right after the piece before it: a name another part '
             f'uses is a global of this mod\'s Lua state, its own helpers stay local.')
    return ['-- ' + l for l in textwrap.wrap(s, 117, break_long_words=False, break_on_hyphens=False)]


def add_modules(part, new):
    raw = open(MAIN, 'rb').read().decode('utf-8')
    eol = '\r\n' if '\r\n' in raw else '\n'
    lines = raw.split(eol)
    i = next(i for i, l in enumerate(lines) if re.match(r'^\s*"' + part + r'",', l))
    assert not any(n in modules() for n in new), f'main.lua MODULES has some of {new} already'
    add = []
    for n in new:
        q = f'    "{n}",'
        add.append(q + ' ' * max(1, 35 - len(q)) + f'-- ({PLANS[part].get("family", part)}.lua\'s next piece: tools/lua_split_part.py)')
    lines[i + 1:i + 1] = add
    with open(MAIN, 'w', encoding='utf-8', newline='') as f:
        f.write(eol.join(lines))


def list_units(part, mn):
    text, _ = norm(os.path.join(SCRIPTS, part + '.lua'))
    lines = text.split('\n')
    plan = PLANS.get(part, {}).get('pieces', [])
    p = parse(text, next((c[1] for _, c, _ in plan[1:] if c and c[0] == 'fields'), None))
    for u in p.units:
        size = u[1] - u[0] + 1
        banner = u[0] > 1 and lines[u[0] - 2].startswith(BANNER)
        if size >= mn or banner:
            print(f'{u[0]:5d}-{u[1]:5d} ({size:4d}) {"do " + str(u[3]) if u[3] is not None else "top "}: {lines[u[0] - 1][:90]}')
    for d in p.dos: print(f'do block: lines {d[0]}-{d[1]}')
    if p.ctor:
        for f in p.ctor['fields']:
            if f[2] - f[1] + 1 >= mn // 2: print(f'field {f[0]}: lines {f[1]}-{f[2]}')


if __name__ == '__main__':
    a = sys.argv[1:]
    if not a or a[0] not in PLANS:
        sys.exit(f'usage: lua_split_part.py <{"|".join(PLANS)}> [--write | --list [N]]')
    if '--list' in a:
        rest = a[a.index('--list') + 1:]
        list_units(a[0], int(rest[0]) if rest else 60)
    else:
        build(a[0], '--write' in a)
