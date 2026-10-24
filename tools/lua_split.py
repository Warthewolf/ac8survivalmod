"""lua_split.py : splits Scripts/main.lua into modules (user, 2026-10-24: "decentralize your main.lua ... split the
runtime into modules with a smaller central controller").

  python -I tools/lua_split.py            analyse only: the plan, what each module shares, any conflict
  python -I tools/lua_split.py --write    write Scripts/sv_*.lua and the new controller main.lua

How the split keeps the behaviour: main.lua was one chunk run top to bottom. The modules are its consecutive pieces,
cut only between top-level statements, and the controller runs them (io + load) in the same order, all in this
mod's own Lua state (UE4SS gives each Lua mod its own). A top-level `local` that another module refers to becomes a
global of that state (its `local ` dropped, nothing else changed); one only its own module uses stays local. So
every name still means the declaration it meant (Lua resolved them by scope; the analysis does the same, with
lua_check.py's parser), and the pieces, `local ` put back, are byte for byte the old file (checked before writing).
VERSION moves to the controller (the packaging scripts read it there).
"""
import os, re, sys
HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, os.path.join(HERE, 'checks'))
from lua_check import tokenize, LuaSyntaxError, KNOWN_GLOBALS, BINARY, RIGHT, UNARY_PRIO

SCRIPTS = os.path.join(HERE, '..', 'mod', 'UE4SS', 'AC8SurvivalMode', 'Scripts')
MAIN = os.path.join(SCRIPTS, 'main.lua')

# (module, first line of its section in main.lua 0.65.1 as it stands before the split, what it holds). The cut snaps
# back to where the comments before that line's statement begin.
PLAN = [
    ('sv_core',        1,    "shared helpers: logging, objects, the menu rows and tables, Survival's flags"),
    ('sv_config',      479,  "the difficulty, CFG (every setting) and survival.ini"),
    ('sv_rows',        1691, "the game's Lua and behaviour scripts, the NPC / ace / special rows added at the menu"),
    ('sv_ai',          2305, "enemy pilots: tiers, kill log, ace hunting, kill pay"),
    ('sv_hud',         2584, "Survival's HUD (round, credits, callouts, warnings)"),
    ('sv_spawn',       2904, "the clock, spawn points, squadrons, flights and the shuttle's spawn"),
    ('sv_anomalies',   3240, "the specials' Lua: MINDRIPPER, AB.L..IN, VALKA and the kinds table (SPC, ANOM)"),
    ('sv_rounds',      4445, "the shuttle countdown, the specials' tick, starting and running rounds, the airfield"),
    ('sv_ladon',       4871, "the Ladons and the hit log"),
    ('sv_leaderboard', 5156, "the run's stats, its summary and the leaderboard (Online edition only)"),
    ('sv_alicorn',     5404, "the Alicorn"),
    ('sv_amphib',      5634, "the amphibious assault"),
    ('sv_flights',     5913, "flight bookkeeping: bombers, ammo, orders, the round clock"),
    ('sv_shop',        6316, "the STORE and the landing shop"),
    ('sv_allies',      6714, "the allies (MOONCHILD, the ships)"),
    ('sv_main',        7060, "kill credits, the probe tick, the keys, the loops that run it all"),
]


class Resolver:
    """lua_check.py's parser with scopes that remember declarations: every name use is tied to the local it means
    (or None for a global), and the main chunk's top-level statements are recorded with their lines."""
    def __init__(self, toks):
        self.t, self.k = toks, 0
        self.scopes = [{}]
        self.depth_fn = 0
        self.decls = []           # (name, line, top-level statement index or None)
        self.refs = []            # (decl index or None, name, line)
        self.top = []             # [start line, end line, [decl indexes]]
        self.cur_top = None

    def peek(self, o=0): return self.t[self.k + o]
    def check(self, v): tk = self.peek(); return tk[0] in ('op', 'kw') and tk[1] == v
    def accept(self, v):
        if self.check(v): self.k += 1; return True
        return False
    def expect(self, v, what=''):
        if not self.accept(v):
            tk = self.peek(); raise LuaSyntaxError(f"line {tk[2]}: '{v}' expected{what} near '{tk[1]}'")
    def name(self):
        tk = self.peek()
        if tk[0] != 'name': raise LuaSyntaxError(f"line {tk[2]}: name expected near '{tk[1]}'")
        self.k += 1; return tk[1]

    def at_top(self): return self.depth_fn == 0 and len(self.scopes) == 2
    def declare(self, n, line=None):
        top = self.cur_top if self.at_top() else None
        self.decls.append((n, line if line is not None else self.peek()[2], top))
        self.scopes[-1][n] = len(self.decls) - 1
        if top is not None: self.top[top][2].append(len(self.decls) - 1)
    def resolve(self, n):
        for s in reversed(self.scopes):
            if n in s: return s[n]
        return None
    def use(self, n, line): self.refs.append((self.resolve(n), n, line))

    def block_follow(self):
        tk = self.peek(); return tk[0] == 'eof' or (tk[0] == 'kw' and tk[1] in ('end', 'else', 'elseif', 'until'))
    def block(self):
        self.scopes.append({})
        top_level = self.depth_fn == 0 and len(self.scopes) == 2
        while not self.block_follow():
            if self.check('return'):
                self.k += 1
                if not self.block_follow() and not self.check(';'): self.explist()
                self.accept(';'); break
            if top_level:
                self.top.append([self.peek()[2], None, []]); self.cur_top = len(self.top) - 1
            self.statement()
            if top_level: self.top[-1][1] = self.t[self.k - 1][2]
        self.scopes.pop()

    def statement(self):
        tk = self.peek(); line = tk[2]
        if self.accept(';'): return
        if self.accept('::'): self.name(); self.expect('::'); return
        if self.accept('break'): return
        if self.accept('goto'): self.name(); return
        if self.accept('do'): self.block(); self.expect('end'); return
        if self.accept('while'): self.expr(); self.expect('do'); self.block(); self.expect('end'); return
        if self.accept('repeat'): self.block(); self.expect('until'); self.expr(); return
        if self.accept('if'):
            self.expr(); self.expect('then'); self.block()
            while self.accept('elseif'): self.expr(); self.expect('then'); self.block()
            if self.accept('else'): self.block()
            self.expect('end'); return
        if self.accept('for'):
            n1 = self.name(); self.scopes.append({})
            if self.accept('='):
                self.expr(); self.expect(','); self.expr()
                if self.accept(','): self.expr()
                self.declare(n1)
            else:
                names = [n1]
                while self.accept(','): names.append(self.name())
                self.expect('in'); self.explist()
                for n in names: self.declare(n)
            self.expect('do'); self.block(); self.expect('end'); self.scopes.pop(); return
        if self.accept('function'):
            n = self.name(); self.use(n, line); method = False
            while self.accept('.'): self.name()
            if self.accept(':'): self.name(); method = True
            self.funcbody(line, method); return
        if self.accept('local'):
            if self.accept('function'):
                n = self.name(); self.declare(n, line); self.funcbody(line); return
            names = [self.name()]
            if self.accept('<'): raise LuaSyntaxError(f'line {line}: attribs (<const> / <close>) not handled by the split')
            while self.accept(','): names.append(self.name())
            if self.accept('='): self.explist()
            for n in names: self.declare(n, line)
            return
        first, kind = self.suffixedexp()
        if self.check('=') or self.check(','):
            while self.accept(','): self.suffixedexp()
            self.expect('='); self.explist(); return

    def funcbody(self, line, method=False):
        self.depth_fn += 1
        self.scopes.append({})
        if method: self.declare('self', line)
        self.expect('(')
        if not self.check(')'):
            while True:
                if self.accept('...'): break
                self.declare(self.name(), line)
                if not self.accept(','): break
        self.expect(')'); self.block(); self.expect('end')
        self.scopes.pop(); self.depth_fn -= 1

    def explist(self):
        self.expr()
        while self.accept(','): self.expr()
    def primaryexp(self):
        tk = self.peek()
        if tk[0] == 'name': self.k += 1; self.use(tk[1], tk[2]); return tk[1], 'name'
        if self.accept('('): self.expr(); self.expect(')'); return None, 'paren'
        raise LuaSyntaxError(f"line {tk[2]}: unexpected symbol near '{tk[1]}'")
    def suffixedexp(self):
        v, kind = self.primaryexp()
        while True:
            if self.accept('.'): self.name(); kind = 'index'
            elif self.accept('['): self.expr(); self.expect(']'); kind = 'index'
            elif self.accept(':'): self.name(); self.args(); kind = 'call'
            elif self.check('(') or self.check('{') or self.peek()[0] == 'string': self.args(); kind = 'call'
            else: return v, kind
    def args(self):
        if self.peek()[0] == 'string': self.k += 1; return
        if self.check('{'): self.table(); return
        self.expect('(')
        if not self.check(')'): self.explist()
        self.expect(')')
    def table(self):
        self.expect('{')
        while not self.check('}'):
            if self.check('['): self.k += 1; self.expr(); self.expect(']'); self.expect('='); self.expr()
            elif self.peek()[0] == 'name' and self.peek(1)[1] == '=' and self.peek(1)[0] == 'op': self.k += 2; self.expr()
            else: self.expr()
            if not (self.accept(',') or self.accept(';')): break
        self.expect('}')
    def simpleexp(self):
        tk = self.peek()
        if tk[0] in ('number', 'string'): self.k += 1; return
        if tk[0] == 'kw' and tk[1] in ('nil', 'true', 'false'): self.k += 1; return
        if self.accept('...'): return
        if self.check('{'): self.table(); return
        if self.accept('function'): self.funcbody(tk[2]); return
        self.suffixedexp()
    def expr(self, limit=0):
        tk = self.peek()
        if (tk[0] == 'kw' and tk[1] == 'not') or (tk[0] == 'op' and tk[1] in ('-', '#', '~')):
            self.k += 1; self.expr(UNARY_PRIO)
        else:
            self.simpleexp()
        while True:
            tk = self.peek(); op = tk[1] if tk[0] in ('op', 'kw') else None
            if op not in BINARY or BINARY[op] <= limit: return
            self.k += 1; self.expr(RIGHT.get(op, BINARY[op]))


BARE = re.compile(r'^local ([A-Za-z_]\w*(?:, *[A-Za-z_]\w*)*)( *(?:--.*)?)$')


def globalise(line):
    """A shared top-level local's statement as a global's, and how: `local x = v` -> `x = v` ('prefix'); a bare
    forward declaration `local a, b  -- why` -> `a, b = nil, nil  -- why` ('bare': a statement Lua accepts; a new
    global is nil anyway)."""
    m = BARE.match(line)
    if m:
        names = [n.strip() for n in m.group(1).split(',')]
        return f"{m.group(1)} = {', '.join(['nil'] * len(names))}{m.group(2)}", 'bare'
    return line[len('local '):], 'prefix'


def localise(line, how):
    """globalise's inverse, by how it was done (the rebuild check)."""
    if how == 'bare':
        m = re.match(r'^([A-Za-z_]\w*(?:, *[A-Za-z_]\w*)*) = (nil(?:, nil)*)( *(?:--.*)?)$', line)
        assert m and len(m.group(1).split(',')) == len(m.group(2).split(',')), line
        return f'local {m.group(1)}{m.group(3)}'
    return 'local ' + line


def analyse(src):
    p = Resolver(tokenize(src))
    p.block()
    assert p.peek()[0] == 'eof'
    lines = src.split('\n')
    # where each top-level statement's lead-in (its comments, blank lines) begins: just after the previous one ends
    lead = [1] + [p.top[i - 1][1] + 1 for i in range(1, len(p.top))]
    cuts = []
    for mod, at, _ in PLAN:
        i = next(i for i, st in enumerate(p.top) if st[0] >= at)
        assert not cuts or i > cuts[-1][2], f"{mod}: its cut ({at}) snaps onto the previous module's"
        cuts.append((mod, lead[i], i))
    module_of_stmt = {}
    for j, (mod, line, i) in enumerate(cuts):
        end = cuts[j + 1][2] if j + 1 < len(cuts) else len(p.top)
        for k in range(i, end): module_of_stmt[k] = mod
    line_module = {}
    for j, (mod, line, _) in enumerate(cuts):
        end = cuts[j + 1][1] if j + 1 < len(cuts) else len(lines) + 1
        for ln in range(line, end): line_module[ln] = mod
    decl_mod = {d: module_of_stmt[top] for d, (n, l, top) in enumerate(p.decls) if top is not None}
    users = {}
    for d, n, ln in p.refs:
        if d in decl_mod: users.setdefault(d, set()).add(line_module[ln])
    shared = {d for d in decl_mod if users.get(d, set()) - {decl_mod[d]}}
    return p, lines, cuts, decl_mod, users, shared, line_module


def main():
    write = '--write' in sys.argv
    src = open(MAIN, encoding='utf-8').read()
    assert 'tools/lua_split.py' not in src[:400], 'main.lua is already the controller: the split has been done'
    p, lines, cuts, decl_mod, users, shared, line_module = analyse(src)
    problems = []
    # every shared declaration's statement: one that starts its line with `local ` (the only edit)
    shared_stmts = sorted({p.decls[d][2] for d in shared})
    for t in shared_stmts:
        ln = p.top[t][0]
        if not lines[ln - 1].startswith('local '):
            problems.append(f'line {ln}: a shared top-level local not at the start of its line: {lines[ln - 1][:60]}')
    top_names = {}
    for d, (n, ln, top) in enumerate(p.decls):
        if top is not None: top_names.setdefault(n, []).append(d)
    globals_after = set()
    for t in shared_stmts:
        for d in p.top[t][2]: globals_after.add(p.decls[d][0])
    for n in globals_after:
        if len(top_names[n]) > 1:
            problems.append(f'{n}: declared at the top level {len(top_names[n])} times (lines '
                            f'{", ".join(str(p.decls[d][1]) for d in top_names[n])}) and shared: rename one')
        if n in KNOWN_GLOBALS:
            problems.append(f'{n}: a shared local named like a Lua / UE4SS global')
    # markers must not straddle a cut
    for j, (mod, line, _) in enumerate(cuts):
        end = cuts[j + 1][1] if j + 1 < len(cuts) else len(lines) + 1
        body = '\n'.join(lines[line - 1:end - 1])
        for a, b in (('ONLINE ONLY BEGIN', 'ONLINE ONLY END'), ('TEST ONLY BEGIN', 'TEST ONLY END')):
            if body.count(a) != body.count(b):
                problems.append(f'{mod}: {a} / {b} unbalanced (a cut falls inside one)')
    for mod, line, i in cuts:
        n_sh = sum(1 for d in shared if decl_mod[d] == mod)
        n_loc = sum(1 for d in decl_mod if decl_mod[d] == mod) - n_sh
        end = next((c[1] for c in cuts if c[1] > line), len(lines) + 1)
        print(f'{mod:15s} lines {line:5d}-{end - 1:5d} ({end - line:5d}): shares {n_sh:3d}, keeps {n_loc:3d} local')
    print(f'{len(shared)} of {len(decl_mod)} top-level locals shared between modules; {len(shared_stmts)} statements lose `local `')
    for pr in problems: print('PROBLEM:', pr)
    if problems: sys.exit(1)
    if not write: return
    drop = {p.top[t][0] for t in shared_stmts}
    version_line = next(i + 1 for i, l in enumerate(lines) if l.startswith('local VERSION = '))
    assert version_line in drop, 'VERSION should be shared'
    out, hows = {}, {}
    for j, (mod, line, _) in enumerate(cuts):
        end = cuts[j + 1][1] if j + 1 < len(cuts) else len(lines) + 1
        body = []
        for ln in range(line, end):
            text = lines[ln - 1]
            if ln == version_line: continue                 # (in the controller)
            if ln in drop:
                text, hows[ln] = globalise(text)
            body.append(text)
        out[mod] = body
    # the pieces with `local ` put back (and VERSION in place) are the old file
    rebuilt = []
    for j, (mod, line, _) in enumerate(cuts):
        end = cuts[j + 1][1] if j + 1 < len(cuts) else len(lines) + 1
        k = 0
        for ln in range(line, end):
            if ln == version_line: rebuilt.append(lines[ln - 1]); continue
            text = out[mod][k]; k += 1
            rebuilt.append(localise(text, hows[ln]) if ln in drop else text)
    assert '\n'.join(rebuilt) == src, 'the pieces do not rebuild the old main.lua'
    version = lines[version_line - 1][len('local '):]
    names = [m for m, _, _ in PLAN]
    for (mod, _, what), (_, line, _) in zip(PLAN, cuts):
        head = (f'-- {mod}.lua: {what}.\n'
                f'-- Part of AC8 Survival Mode\'s runtime, run by main.lua in order ({", ".join(names)}); a name\n'
                f'-- another part uses is a global of this mod\'s Lua state, its own helpers stay local (tools/lua_split.py).\n')
        with open(os.path.join(SCRIPTS, mod + '.lua'), 'w', encoding='utf-8', newline='') as f:
            f.write(head + '\n'.join(out[mod]) + ('\n' if not out[mod] or out[mod][-1] != '' else ''))
    ctrl = f'''-- AC8 Survival Mode - runtime (UE4SS Lua half; the native half is dlls\\main.dll)
-- main.lua: the controller (tools/lua_split.py; user, 2026-10-24: "split the runtime into modules with a smaller
-- central controller"). The runtime is in Scripts/sv_*.lua, run here in MODULES' order into this mod's own Lua
-- state (UE4SS gives each Lua mod its own): a name one part shares with the others is a global of that state, each
-- part's own helpers stay local to it. A part that fails to load stops the rest, as one file used to.
-- (Hard rule 23 counts locals per part now: python tools/checks/lua_check.py Scripts/*.lua checks them all.)
{version}

local MODULES = {{
''' + ''.join(f'    "{m}",\n' for m in names) + '''}

local DIR = debug.getinfo(1, "S").source:match("^@(.*[/\\\\])") or ""
-- each part read (io, as the ini is) and run as a chunk of its own named by its path, so debug.getinfo (SCRIPT_DIR)
-- and error lines point at the part
local function run(m)
    local path = DIR .. m .. ".lua"
    local f = io.open(path, "rb")
    if not f then return false, "not found: " .. path end
    local src = f:read("a")
    f:close()
    local chunk, err = load(src, "@" .. path, "t")
    if not chunk then return false, err end
    return pcall(chunk)
end
for _, m in ipairs(MODULES) do
    local ok, err = run(m)
    if not ok then
        print("[AC8SurvivalMode] " .. m .. ".lua failed to load: " .. tostring(err) .. "\\n")
        error(err, 0)
    end
end
'''
    with open(MAIN, 'w', encoding='utf-8', newline='') as f:
        f.write(ctrl)
    print(f'wrote main.lua (controller) and {len(names)} modules to {os.path.normpath(SCRIPTS)}')


if __name__ == '__main__':
    main()
