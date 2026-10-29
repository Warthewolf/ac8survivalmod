"""build_hash.py <Mods folder> [--list] : the build hash of a staged Survival Mode release (or an installed one), as the
native runtime works it out in the game (runtime/build_hash.c; the two must agree: tools/checks/build_hash_test.sh).

<Mods folder> holds AC8SurvivalMode\\ and IoStoreLoaderMod\\SurvivalMode\\ (a release zip's ue4ss/Mods, or the game's
ue4ss\\Mods). Prints the hash (64 hex characters); --list prints each file hashed and its size first.

The leaderboard Worker counts a run only from a build the user registered on its /admin page (leaderboard/README.md):
tools/package_release.sh runs this on each release it stages and writes <zip>.buildhash.txt for that.

The stream hashed (SHA-256), for each file in this order:   <name> \\0 <its size in decimal> \\0 <its bytes>
with <name> the file's canonical name (ASCII letters lowercased, forward slashes, UTF-8):
  ac8survivalmode/scripts/<file>      every *.lua in AC8SurvivalMode/Scripts, by lowercased name in byte order
  ac8survivalmode/scripts/ai/<file>   every *.lua in AC8SurvivalMode/Scripts/ai, the same way
  ac8survivalmode/config/survival.default.ini
  ac8survivalmode/dlls/main.dll
  iostoreloadermod/survivalmode/survivalmode_p.utoc, then survivalmode_p.ucas
"""
import hashlib
import os
import sys

_LOWER = {c: c + 32 for c in range(ord('A'), ord('Z') + 1)}


def ascii_lower(s):
    """A-Z only (as the runtime's BhLowerA): other letters stay as they are"""
    return s.translate(_LOWER)


def _scripts(folder, prefix):
    try:
        entries = list(os.scandir(folder))
    except FileNotFoundError:
        return []
    names = [e.name for e in entries if e.is_file() and len(e.name) >= 5 and ascii_lower(e.name).endswith('.lua')]
    names.sort(key=lambda n: ascii_lower(n).encode('utf-8'))
    return [(prefix + ascii_lower(n), os.path.join(folder, n)) for n in names]


def files(mods):
    root = os.path.join(mods, 'AC8SurvivalMode')
    io = os.path.join(mods, 'IoStoreLoaderMod', 'SurvivalMode')
    out = _scripts(os.path.join(root, 'Scripts'), 'ac8survivalmode/scripts/')
    if not out:
        raise SystemExit(f'build_hash: no scripts in {os.path.join(root, "Scripts")}')
    out += _scripts(os.path.join(root, 'Scripts', 'ai'), 'ac8survivalmode/scripts/ai/')
    for name, path in (('ac8survivalmode/config/survival.default.ini', os.path.join(root, 'config', 'survival.default.ini')),
                       ('ac8survivalmode/dlls/main.dll', os.path.join(root, 'dlls', 'main.dll')),
                       ('iostoreloadermod/survivalmode/survivalmode_p.utoc', os.path.join(io, 'SurvivalMode_P.utoc')),
                       ('iostoreloadermod/survivalmode/survivalmode_p.ucas', os.path.join(io, 'SurvivalMode_P.ucas'))):
        if not os.path.isfile(path):
            raise SystemExit(f'build_hash: missing {path}')
        out.append((name, path))
    return out


def build_hash(mods, listing=None):
    h = hashlib.sha256()
    for name, path in files(mods):
        with open(path, 'rb') as f:
            data = f.read()
        h.update(name.encode('utf-8') + b'\0' + str(len(data)).encode('ascii') + b'\0')
        h.update(data)
        if listing is not None:
            listing.append((name, len(data)))
    return h.hexdigest()


if __name__ == '__main__':
    args = [a for a in sys.argv[1:] if not a.startswith('--')]
    if len(args) != 1:
        raise SystemExit('usage: build_hash.py <Mods folder> [--list]')
    listing = [] if '--list' in sys.argv else None
    hx = build_hash(args[0], listing)
    for name, size in listing or []:
        print(f'{size:>10}  {name}')
    print(hx)
