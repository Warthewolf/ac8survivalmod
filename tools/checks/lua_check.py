"""lua_check.py : Lua 5.4 syntax check (no Lua on the build machine).

  python lua_check.py <file.lua> ...

A tokenizer and recursive-descent parser for the Lua 5.4 grammar. It reports the first syntax error per file with its
line, and warns about globals that are assigned but never declared local (typos) and locals used before their
declaration line. Exit code 1 on a syntax error.
"""
import re, sys

KEYWORDS = {'and', 'break', 'do', 'else', 'elseif', 'end', 'false', 'for', 'function', 'goto', 'if', 'in', 'local',
            'nil', 'not', 'or', 'repeat', 'return', 'then', 'true', 'until', 'while'}
OPS = ['...', '..', '::', '<<', '>>', '//', '==', '~=', '<=', '>=', '+', '-', '*', '/', '%', '^', '#', '&', '~', '|',
       '<', '>', '=', '(', ')', '{', '}', '[', ']', ';', ':', ',', '.']
BINARY = {'or': 1, 'and': 2, '<': 3, '>': 3, '<=': 3, '>=': 3, '~=': 3, '==': 3, '|': 4, '~': 5, '&': 6, '<<': 7,
          '>>': 7, '..': 9, '+': 10, '-': 10, '*': 11, '/': 11, '//': 11, '%': 11, '^': 14}
RIGHT = {'..': 8, '^': 13}          # right-associative: right binding power
UNARY_PRIO = 12


class LuaSyntaxError(Exception):
    pass


def tokenize(src):
    toks, i, line, n = [], 0, 1, len(src)
    num = re.compile(r'0[xX](?:[0-9a-fA-F]*\.?[0-9a-fA-F]*)(?:[pP][+-]?\d+)?|(?:\d+\.?\d*|\.\d+)(?:[eE][+-]?\d+)?')
    name = re.compile(r'[A-Za-z_][A-Za-z_0-9]*')
    while i < n:
        c = src[i]
        if c == '\n': line += 1; i += 1; continue
        if c in ' \t\r\f\v': i += 1; continue
        if src.startswith('--', i):
            m = re.match(r'--\[(=*)\[', src[i:])
            if m:
                close = ']' + m.group(1) + ']'
                j = src.find(close, i)
                if j < 0: raise LuaSyntaxError(f'line {line}: unfinished long comment')
                line += src.count('\n', i, j); i = j + len(close)
            else:
                j = src.find('\n', i); i = n if j < 0 else j
            continue
        m = re.match(r'\[(=*)\[', src[i:])
        if m:
            close = ']' + m.group(1) + ']'
            j = src.find(close, i)
            if j < 0: raise LuaSyntaxError(f'line {line}: unfinished long string')
            toks.append(('string', src[i:j + len(close)], line)); line += src.count('\n', i, j); i = j + len(close)
            continue
        if c in '"\'':
            j = i + 1
            while j < n and src[j] != c:
                if src[j] == '\\':
                    if src[j + 1:j + 2] == 'z':
                        j += 2
                        while j < n and src[j] in ' \t\r\n': line += src[j] == '\n'; j += 1
                        continue
                    e = src[j + 1:j + 2]
                    if e == '\n': line += 1
                    elif e == 'x' and not re.match(r'[0-9a-fA-F]{2}', src[j + 2:j + 4]):
                        raise LuaSyntaxError(f'line {line}: hexadecimal digit expected in \\x escape')
                    elif e == 'u' and not re.match(r'\{[0-9a-fA-F]+\}', src[j + 2:]):
                        raise LuaSyntaxError(f'line {line}: invalid \\u escape')
                    elif e not in 'abfnrtv\\"\'\rxu' and not e.isdigit():
                        raise LuaSyntaxError(f'line {line}: invalid escape sequence \\{e}')
                    j += 2; continue
                if src[j] == '\n': raise LuaSyntaxError(f'line {line}: unfinished string')
                j += 1
            if j >= n: raise LuaSyntaxError(f'line {line}: unfinished string')
            toks.append(('string', src[i:j + 1], line)); i = j + 1; continue
        if c.isdigit() or (c == '.' and i + 1 < n and src[i + 1].isdigit()):
            m = num.match(src, i)
            toks.append(('number', m.group(), line)); i = m.end(); continue
        m = name.match(src, i)
        if m:
            w = m.group()
            toks.append(('kw' if w in KEYWORDS else 'name', w, line)); i = m.end(); continue
        for op in OPS:
            if src.startswith(op, i):
                toks.append(('op', op, line)); i += len(op); break
        else:
            raise LuaSyntaxError(f'line {line}: unexpected character {c!r}')
    toks.append(('eof', '<eof>', line))
    return toks


class Parser:
    def __init__(self, toks):
        self.t, self.k = toks, 0
        self.scopes = [set()]
        # Lua's limit: at most 200 locals in scope at once in one function (the main chunk too; MAXVARS). One entry per
        # function, one count per open block. A 0.27.2 main.lua with 205 failed to load in game ("too many local variables").
        self.frames = [[0]]
        self.max_locals = 0
        self.globals_set = {}
        self.used = []

    # token helpers
    def peek(self, o=0): return self.t[self.k + o]
    def check(self, v): tk = self.peek(); return tk[0] in ('op', 'kw') and tk[1] == v
    def accept(self, v):
        if self.check(v): self.k += 1; return True
        return False
    def expect(self, v, what=''):
        if not self.accept(v):
            tk = self.peek()
            raise LuaSyntaxError(f"line {tk[2]}: '{v}' expected{what} near '{tk[1]}'")
    def name(self):
        tk = self.peek()
        if tk[0] != 'name': raise LuaSyntaxError(f"line {tk[2]}: name expected near '{tk[1]}'")
        self.k += 1; return tk[1]

    # scopes
    def declare(self, n, slots=1):
        self.scopes[-1].add(n)
        self.frames[-1][-1] += slots
        active = sum(self.frames[-1])
        if len(self.frames) == 1: self.max_locals = max(self.max_locals, active)
        if active > 200:
            raise LuaSyntaxError(f"line {self.peek()[2]}: too many local variables (limit is 200) in "
                                 f"{'the main chunk' if len(self.frames) == 1 else 'a function'}: declare fewer "
                                 f"(e.g. put helpers in a do ... end block)")
    def is_local(self, n): return any(n in s for s in self.scopes)
    def use(self, n, line):
        if not self.is_local(n): self.used.append((n, line))

    # grammar
    def block_follow(self):
        tk = self.peek()
        return tk[0] == 'eof' or (tk[0] == 'kw' and tk[1] in ('end', 'else', 'elseif', 'until'))

    def block(self):
        self.scopes.append(set())
        self.frames[-1].append(0)
        while not self.block_follow():
            if self.check('return'):
                self.k += 1
                if not self.block_follow() and not self.check(';'): self.explist()
                self.accept(';')
                break
            self.statement()
        self.scopes.pop()
        self.frames[-1].pop()

    def statement(self):
        tk = self.peek(); line = tk[2]
        if self.accept(';'): return
        if self.accept('::'): self.name(); self.expect('::'); return
        if self.accept('break'): return
        if self.accept('goto'): self.name(); return
        if self.accept('do'): self.block(); self.expect('end', f' (to close do at line {line})'); return
        if self.accept('while'):
            self.expr(); self.expect('do'); self.block(); self.expect('end', f' (to close while at line {line})'); return
        if self.accept('repeat'):
            self.block(); self.expect('until', f' (to close repeat at line {line})'); self.expr(); return
        if self.accept('if'):
            self.expr(); self.expect('then'); self.block()
            while self.accept('elseif'): self.expr(); self.expect('then'); self.block()
            if self.accept('else'): self.block()
            self.expect('end', f' (to close if at line {line})'); return
        if self.accept('for'):
            n1 = self.name()
            self.scopes.append(set())
            self.frames[-1].append(0)
            if self.accept('='):
                self.expr(); self.expect(','); self.expr()
                if self.accept(','): self.expr()
                self.declare('(for state)', 3)              # the loop's hidden control slots
                self.declare(n1)
            else:
                names = [n1]
                while self.accept(','): names.append(self.name())
                self.expect('in'); self.explist()
                self.declare('(for state)', 4)
                for n in names: self.declare(n)
            self.expect('do'); self.block(); self.expect('end', f' (to close for at line {line})')
            self.scopes.pop(); self.frames[-1].pop(); return
        if self.accept('function'):
            n = self.name(); full = n; method = False
            self.use(n, line)
            while self.accept('.'): full += '.' + self.name()
            if self.accept(':'): full += ':' + self.name(); method = True
            if '.' not in full and ':' not in full and not self.is_local(n): self.globals_set.setdefault(n, line)
            self.funcbody(line, method); return
        if self.accept('local'):
            if self.accept('function'):
                n = self.name(); self.declare(n); self.funcbody(line); return
            names = [self.name()]
            if self.accept('<'): self.name(); self.expect('>')
            while self.accept(','):
                names.append(self.name())
                if self.accept('<'): self.name(); self.expect('>')
            if self.accept('='): self.explist()
            for n in names: self.declare(n)
            return
        # exprstat: call or assignment
        first, kind = self.suffixedexp()
        if self.check('=') or self.check(','):
            targets = [(first, kind)]
            while self.accept(','): targets.append(self.suffixedexp())
            for tgt, kd in targets:
                if kd not in ('name', 'index'): raise LuaSyntaxError(f'line {line}: cannot assign to that expression')
                if kd == 'name' and not self.is_local(tgt): self.globals_set.setdefault(tgt, line)
            self.expect('='); self.explist(); return
        if kind != 'call': raise LuaSyntaxError(f"line {line}: syntax error near '{self.peek()[1]}' (not a call or assignment)")

    def funcbody(self, line, method=False):
        self.scopes.append({'self'} if method else set())
        self.frames.append([1 if method else 0])
        self.expect('(')
        if not self.check(')'):
            while True:
                if self.accept('...'): break
                self.declare(self.name())
                if not self.accept(','): break
        self.expect(')')
        self.block()
        self.expect('end', f' (to close function at line {line})')
        self.scopes.pop()
        self.frames.pop()

    def explist(self):
        self.expr()
        while self.accept(','): self.expr()

    def primaryexp(self):
        tk = self.peek()
        if tk[0] == 'name':
            self.k += 1; self.use(tk[1], tk[2]); return tk[1], 'name'
        if self.accept('('):
            self.expr(); self.expect(')'); return None, 'paren'
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
        line = self.peek()[2]
        self.expect('{')
        while not self.check('}'):
            if self.check('['):
                self.k += 1; self.expr(); self.expect(']'); self.expect('='); self.expr()
            elif self.peek()[0] == 'name' and self.peek(1)[1] == '=' and self.peek(1)[0] == 'op':
                self.k += 2; self.expr()
            else:
                self.expr()
            if not (self.accept(',') or self.accept(';')): break
        self.expect('}', f' (to close table at line {line})')

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
            tk = self.peek()
            op = tk[1] if tk[0] in ('op', 'kw') else None
            if op not in BINARY or BINARY[op] <= limit: return
            self.k += 1
            self.expr(RIGHT.get(op, BINARY[op]))


KNOWN_GLOBALS = {
    # Lua 5.4
    'assert', 'collectgarbage', 'error', 'getmetatable', 'ipairs', 'load', 'next', 'pairs', 'pcall', 'print', 'rawequal',
    'rawget', 'rawlen', 'rawset', 'require', 'select', 'setmetatable', 'tonumber', 'tostring', 'type', 'xpcall', '_G',
    'math', 'string', 'table', 'os', 'io', 'coroutine', 'utf8', 'debug', 'package',
    # UE4SS 3.0.1
    'StaticFindObject', 'FindFirstOf', 'FindAllOf', 'FindObject', 'FindObjects', 'NotifyOnNewObject', 'LoopAsync',
    'ExecuteInGameThread', 'ExecuteWithDelay', 'ExecuteAsync', 'RegisterKeyBind', 'IsKeyBindRegistered', 'Key',
    'ModifierKey', 'FName', 'FText', 'LoadAsset', 'RegisterHook', 'UnregisterHook', 'RegisterCustomEvent',
    'StaticConstructObject', 'CreateInvalidObject', 'IterateGameDirectories', 'DumpAllObjects', 'GenerateSDK',
    # dlls\main.dll (runtime 0.10.0)
    'SV_Version', 'SV_Spawn', 'SV_SetAircraft', 'SV_UnitAlive', 'SV_LogUnits', 'SV_Reset', 'SV_Ammo', 'SV_SetAmmo', 'SV_FreeRestock', 'SV_GameLua', 'SV_GameLuaState',
    'SV_PlayBGM', 'SV_BGM', 'SV_Event', 'SV_MusicPlayer', 'SV_MusicClock', 'Inherit', 'CppObjectBase', 'FVector', 'ELiveAIManeuverSpeedType', 'EArithmeticKeyOperation', 'SV_SetText', 'SV_ShopRequest', 'SV_BGMNames',
}


def check(path):
    src = open(path, encoding='utf-8').read()
    try:
        p = Parser(tokenize(src))
        p.block()
        if p.peek()[0] != 'eof':
            tk = p.peek(); raise LuaSyntaxError(f"line {tk[2]}: '<eof>' expected near '{tk[1]}'")
    except LuaSyntaxError as e:
        print(f'{path}: SYNTAX ERROR {e}')
        return False
    print(f'{path}: syntax ok (main chunk: at most {p.max_locals} of 200 locals in scope)')
    for n, line in sorted(p.globals_set.items(), key=lambda kv: kv[1]):
        print(f'  note: global assigned: {n} (line {line})')
    seen = set()
    for n, line in p.used:
        if n not in KNOWN_GLOBALS and n not in p.globals_set and n not in seen:
            seen.add(n); print(f'  WARNING: unknown global {n} (line {line}): a typo, or a local used before it is declared')
    return True


if __name__ == '__main__':
    ok = all([check(f) for f in sys.argv[1:]])
    sys.exit(0 if ok else 1)
