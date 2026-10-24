"""ini_check.py [survival.default.ini] [sv_config.lua] : every setting in survival.default.ini is one Scripts/sv_config.lua's
CFG has, with a value of its kind (there's no Lua on the build machine, so CFG's table literal is read here as
Scripts/sv_config.lua's loadIni reads the ini: sections through INI_ALIAS and "shop." -> "shop.items.", keys any case).
A switched-off line (";key = value") is checked as if it were on. Exit 1 on the first problem list.
"""
import os
import re
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
SCRIPTS = os.path.join(HERE, '..', '..', 'mod', 'UE4SS', 'AC8SurvivalMode', 'Scripts')
INI = os.path.join(HERE, '..', '..', 'mod', 'UE4SS', 'AC8SurvivalMode', 'config', 'survival.default.ini')

TOKEN = re.compile(r'''\s+|--\[\[.*?\]\]|--[^\n]*|"(?:\\.|[^"\\])*"|'(?:\\.|[^'\\])*'|0x[0-9a-fA-F]+|\d+\.\d*(?:[eE][-+]?\d+)?|\d+(?:[eE][-+]?\d+)?|\.\d+|[A-Za-z_][\w]*|\.\.|[{}\[\]=,;().+\-*/%#<>~^:]''', re.S)


def tokens(src):
    out, pos = [], 0
    while pos < len(src):
        m = TOKEN.match(src, pos)
        if not m: raise SyntaxError(f'bad character at {pos}: {src[pos:pos + 20]!r}')
        t = m.group(0)
        pos = m.end()
        if t.isspace() or t.startswith('--'): continue
        out.append(t)
    return out


class Parser:
    def __init__(self, toks): self.t, self.i = toks, 0
    def peek(self): return self.t[self.i] if self.i < len(self.t) else None
    def take(self, want=None):
        t = self.t[self.i]
        if want is not None and t != want: raise SyntaxError(f'wanted {want!r}, got {t!r} near {self.t[self.i - 5:self.i + 5]}')
        self.i += 1
        return t

    def value(self):
        t = self.peek()
        if t == '{': return self.table()
        if t == '-': self.take(); return -self.value()
        self.take()
        if t[0] in '"\'': return t[1:-1]
        if t in ('true', 'false'): return t == 'true'
        if t == 'nil': return None
        if re.match(r'^(0x|\d|\.\d)', t): return int(t, 16) if t.startswith('0x') else (float(t) if re.search(r'[.eE]', t) else int(t))
        # a name or an expression the checker doesn't evaluate (math.huge, ...): kept as an opaque value
        while self.peek() in ('.', '(', ')') or (self.peek() and re.match(r'^[A-Za-z_]', self.peek()) and self.t[self.i - 1] == '.'):
            self.take()
        return ('expr', t)

    def table(self):
        self.take('{')
        arr, keyed = [], {}
        while self.peek() != '}':
            if self.peek() == '[':
                self.take('['); k = self.value(); self.take(']'); self.take('='); keyed[k] = self.value()
            elif re.match(r'^[A-Za-z_]\w*$', self.peek()) and self.t[self.i + 1] == '=':
                k = self.take(); self.take('='); keyed[k] = self.value()
            else:
                arr.append(self.value())
            if self.peek() in (',', ';'): self.take()
        self.take('}')
        return {'arr': arr, 'keyed': keyed}


def cfg_table(path):
    src = open(path, encoding='utf-8').read()
    start = src.index('\nCFG = {') + len('\nCFG = ')
    p = Parser(tokens(src[start:]))
    return p.table(), src


def find(t, name):
    """A keyed field of table t by name, any case (as loadIni's iniSection / its key search)."""
    for k, v in t['keyed'].items():
        if isinstance(k, str) and k.lower() == name.lower(): return k, v
    return None, None


def main(ini_path, cfg_path):
    cfg, src = cfg_table(cfg_path)
    alias = dict(re.findall(r'(?:\[\s*"([^"]+)"\s*\]|(\w+))\s*=\s*"([^"]*)"', src[src.index('local INI_ALIAS'):src.index('local INI_RETIRED')]) and
                 [((a or b).lower(), c) for a, b, c in re.findall(r'(?:\[\s*"([^"]+)"\s*\]|(\w+))\s*=\s*"([^"]*)"',
                                                                  src[src.index('local INI_ALIAS'):src.index('local INI_RETIRED')])])
    problems, section, table, n = [], None, None, 0
    for no, raw in enumerate(open(ini_path, encoding='utf-8'), 1):
        line = raw.strip()
        if line.startswith(';OFFLINE:'): line = line[len(';OFFLINE:'):].strip()
        m = re.match(r'^\[\s*(.+?)\s*\]$', line)
        if m:
            section = m.group(1)
            path = alias.get(section.lower(), re.sub(r'^shop\.', 'shop.items.', section.lower()))
            table = cfg
            for part in [p for p in path.split('.') if p]:
                _, nxt = find(table, part)
                if not isinstance(nxt, dict): table = None; break
                table = nxt
            if table is None: problems.append(f'line {no}: no CFG table for [{section}] ({path})')
            continue
        m = re.match(r'^;?([\w]+)\s*=\s*(.*)$', line)          # (a setting: ';key = value'; '; text' is a note)
        if not m or table is None: continue
        key, val = m.group(1), m.group(2).strip()
        n += 1
        if section.lower() == 'squadrons':
            continue
        k, old = find(table, key)
        if k is None:
            problems.append(f'line {no}: [{section}] {key}: CFG has no such field'); continue
        ok = True
        if isinstance(old, bool): ok = val.lower() in ('true', 'false', 'yes', 'no', 'on', 'off', '1', '0')
        elif isinstance(old, (int, float)): ok = re.match(r'^-?\d+(\.\d+)?$', val) is not None
        elif isinstance(old, dict):
            items = [x.strip() for x in val.split(',') if x.strip()]
            first = old['arr'][0] if old['arr'] else None
            if old['keyed'] or first is None or isinstance(first, dict): ok = False
            elif isinstance(first, (int, float)): ok = all(re.match(r'^-?\d+(\.\d+)?$', x) for x in items)
        elif isinstance(old, str): ok = True
        else: ok = False
        if not ok: problems.append(f'line {no}: [{section}] {key} = {val}: not a {type(old).__name__} setting')
    for p in problems: print('INI CHECK:', p)
    print(f'ini check: {n} settings in {os.path.basename(ini_path)}, {len(problems)} problems')
    return 1 if problems else 0


if __name__ == '__main__':
    a = sys.argv[1:]
    sys.exit(main(a[0] if a else INI, a[1] if len(a) > 1 else os.path.join(SCRIPTS, 'sv_config.lua')))
