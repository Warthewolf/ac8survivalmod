"""rt_format_check.py : hard rule 43 checked over the native runtime's sources (runtime/*.c, *.h), no game needed.
The runtime's formatter (runtime/vfmt.h VFmt, behind Log, Crumb and flight_guards.c's TcAppend) knows only %s %d %u %x
%p (and %% for a percent sign). Anything else, a width or a length modifier too (%04x, %ld, %ls, %f), takes no argument,
so every later argument is read as the wrong one: 0.18.0's sound log used %u (unknown then) and crashed AC8 on VALKA's
first sound (2026-10-24). A format with more specifiers than arguments reads past them the same way.
For each Log( / Crumb( / TcAppend( call: the format (string literals, joined; each side of a ? : when both are literals)
  - FAILS on a specifier VFmt doesn't know, and on more specifiers than arguments;
  - notes a format that isn't a literal (can't be checked here) and fewer specifiers than arguments (harmless: VFmt reads
    only what the format names; two ternary formats do it on purpose).
Run: python -X utf8 -I tools/checks/rt_format_check.py [-v]"""
import glob
import os
import re
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
RT = os.path.join(HERE, '..', '..', 'runtime')
CALLS = {'Log': 0, 'Crumb': 0, 'TcAppend': 2}        # function -> the format's argument index
KNOWN = set('sdux p%'.replace(' ', ''))


def strip_comments(src):
    """Comments blanked (newlines kept, so line numbers hold); strings and char literals left as they are."""
    out, i, n = [], 0, len(src)
    while i < n:
        c = src[i]
        if c in '"\'':
            j = i + 1
            while j < n and src[j] != c:
                j += 2 if src[j] == '\\' else 1
            out.append(src[i:j + 1]); i = j + 1
        elif src.startswith('//', i):
            j = src.find('\n', i); j = n if j < 0 else j
            out.append(' ' * (j - i)); i = j
        elif src.startswith('/*', i):
            j = src.find('*/', i + 2); j = n if j < 0 else j + 2
            out.append(re.sub(r'[^\n]', ' ', src[i:j])); i = j
        else:
            out.append(c); i += 1
    return ''.join(out)


def split_args(src, start):
    """The call's arguments from just after its '(' -> ([arg text ...], index after ')'), or None if unbalanced."""
    depth, i, n, args, cur = 0, start, len(src), [], start
    while i < n:
        c = src[i]
        if c in '"\'':
            j = i + 1
            while j < n and src[j] != c:
                j += 2 if src[j] == '\\' else 1
            i = j + 1; continue
        if c in '([{': depth += 1
        elif c in ')]}':
            if depth == 0:
                args.append(src[cur:i]); return [a.strip() for a in args], i + 1
            depth -= 1
        elif c == ',' and depth == 0:
            args.append(src[cur:i]); cur = i + 1
        i += 1
    return None


LIT = re.compile(r'L"((?:[^"\\]|\\.)*)"')


def literal(expr):
    """The joined text when expr is only wide string literals (L"a" L"b"), else None."""
    rest = LIT.sub('', expr).strip()
    if rest: return None
    return ''.join(LIT.findall(expr))


def alternatives(expr):
    """[format text, ...]: one for a literal, two for cond ? L"a" : L"b", none when it can't be read."""
    t = literal(expr)
    if t is not None: return [t]
    # cond ? a : b, the ? and : found outside strings and brackets (a format's text has colons of its own)
    q = c = None
    depth, i, n = 0, 0, len(expr)
    while i < n:
        ch = expr[i]
        if ch in '"\'':
            j = i + 1
            while j < n and expr[j] != ch:
                j += 2 if expr[j] == '\\' else 1
            i = j + 1; continue
        if ch in '([{': depth += 1
        elif ch in ')]}': depth -= 1
        elif depth == 0 and ch == '?' and q is None: q = i
        elif depth == 0 and ch == ':' and q is not None and c is None: c = i
        i += 1
    if q is not None and c is not None:
        a, b = literal(expr[q + 1:c].strip()), literal(expr[c + 1:].strip())
        if a is not None and b is not None: return [a, b]
    return []


def specifiers(fmt):
    """[(the character after %, its offset), ...], %% left out"""
    out, i = [], 0
    while i < len(fmt):
        if fmt[i] == '%':
            if i + 1 >= len(fmt): out.append(('', i)); break
            if fmt[i + 1] != '%': out.append((fmt[i + 1], i))
            i += 2
        else:
            i += 1
    return out


def main(argv):
    verbose = '-v' in argv
    files = sorted(glob.glob(os.path.join(RT, '*.c')) + glob.glob(os.path.join(RT, '*.h')))
    calls = bad = notes = 0
    for path in files:
        src = strip_comments(open(path, encoding='utf-8', errors='replace').read())
        rel = os.path.relpath(path, os.path.join(RT, '..')).replace(os.sep, '/')
        for m in re.finditer(r'(?<![\w.>])(Log|Crumb|TcAppend)\s*\(', src):
            name = m.group(1)
            line = src.count('\n', 0, m.start()) + 1
            before = src[max(0, m.start() - 40):m.start()]
            if re.search(r'\b(static|void|define)\s*$', before) or re.search(r'\bvoid\s+$', before): continue  # (its definition)
            got = split_args(src, m.end())
            if got is None: continue
            args, _ = got
            k = CALLS[name]
            if len(args) <= k:
                continue
            fmt_expr, rest = args[k], [a for a in args[k + 1:] if a]
            alts = alternatives(fmt_expr)
            calls += 1
            if not alts:
                notes += 1
                if verbose: print(f'  note {rel}:{line}: {name}\'s format isn\'t a literal ({fmt_expr[:60]}): not checked')
                continue
            for fmt in alts:
                sp = specifiers(fmt)
                unknown = [c for c, _ in sp if c not in KNOWN]
                if unknown:
                    bad += 1
                    print(f'  FAIL {rel}:{line}: {name}("{fmt[:70]}"): %{unknown[0] or "<end>"} isn\'t a specifier VFmt knows '
                          f'(only %s %d %u %x %p): it takes no argument and every later one is read wrong (hard rule 43)')
                if len(sp) > len(rest):
                    bad += 1
                    print(f'  FAIL {rel}:{line}: {name}("{fmt[:70]}"): {len(sp)} specifiers but {len(rest)} arguments')
                elif len(sp) < len(rest) and len(alts) == 1:
                    notes += 1
                    if verbose: print(f'  note {rel}:{line}: {name}: {len(rest)} arguments for {len(sp)} specifiers (the extra are never read)')
    print(f'rt format check: {calls} Log / Crumb / TcAppend calls in {len(files)} files, {bad} problems'
          f'{f", {notes} notes (-v)" if notes else ""}')
    return 1 if bad else 0


if __name__ == '__main__':
    sys.exit(main(sys.argv[1:]))
