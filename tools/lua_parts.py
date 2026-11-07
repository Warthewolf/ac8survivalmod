"""lua_parts.py : the runtime's parts as main.lua runs them (Scripts/main.lua MODULES), for the tools that read or
edit one part's text. A part split by tools/lua_split_part.py is a family run one after the other (sv_coop.lua,
sv_coop_joiner.lua, ...: the part, then the MODULES right after it named <part>_<topic>), so what a tool looks for
may be in any of its pieces. tools/checks/parts.lua is the Lua tests' copy of this.

  modules(scripts)                      main.lua's MODULES, in order
  family(scripts, part)                 the part's pieces' paths (part: 'sv_config' or 'sv_config.lua')
  read(scripts, part)                   the family's text, its pieces in order joined by a newline
  sub(scripts, part, old, new, what)    `old` must be in the family once: replaced in the piece holding it, in place
  subn(scripts, part, pattern, repl)    re.subn on each piece, in place; the count over the family
"""
import os
import re


def modules(scripts):
    p = os.path.join(scripts, 'main.lua')
    if not os.path.exists(p): return []
    src = open(p, encoding='utf-8').read()
    if 'local MODULES = {' not in src: return []
    body = src[src.index('local MODULES = {'):]
    body = body[:body.index('\n}')]
    return re.findall(r'^\s*"(\w+)",', body, re.M)


def family(scripts, part):
    part = part[:-4] if part.endswith('.lua') else part
    mods = modules(scripts)
    names = [part]
    if part in mods:
        i = mods.index(part) + 1
        while i < len(mods) and mods[i].startswith(part + '_'):
            names.append(mods[i]); i += 1
    return [os.path.join(scripts, n + '.lua') for n in names]


def read(scripts, part):
    return '\n'.join(open(p, encoding='utf-8').read() for p in family(scripts, part))


def sub(scripts, part, old, new, what):
    """the one `old` of the family replaced by `new` (bytes kept as they are: newline='')"""
    texts = [(p, open(p, encoding='utf-8', newline='').read()) for p in family(scripts, part)]
    n = sum(s.count(old) for _, s in texts)
    assert n == 1, f'{what}: {n} matches for {old!r} in {", ".join(os.path.basename(p) for p, _ in texts)}'
    for p, s in texts:
        if old in s:
            open(p, 'w', encoding='utf-8', newline='').write(s.replace(old, new))


def subn(scripts, part, pattern, repl, flags=0):
    total = 0
    for p in family(scripts, part):
        s = open(p, encoding='utf-8', newline='').read()
        s2, n = re.subn(pattern, repl, s, flags=flags)
        if n:
            open(p, 'w', encoding='utf-8', newline='').write(s2)
            total += n
    return total
