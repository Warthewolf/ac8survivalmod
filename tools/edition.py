"""edition.py online|offline <file>... : makes a file one edition's, in place (tools/package_release.sh runs it on the
staged copies, never on the sources).

The Nexus release comes in two editions (user, 2026-10-23: "One is Online Mode (game can send files to the cloudflare
server) Two is Offline Mode (None of the Code for sending the files remains)"). In the sources:
  - a line holding `ONLINE ONLY BEGIN` up to the next line holding `ONLINE ONLY END` is the Online edition's only;
  - a line whose text starts with `OFFLINE:` (after its comment mark: `--OFFLINE: ...` in Lua, `;OFFLINE: ...` in the
    ini, `OFFLINE: ...` in the readme) is the Offline edition's only, written as a comment so the sources run as Online.
online: the marker lines and the OFFLINE: lines go. offline: the ONLINE ONLY blocks go (markers too), and each OFFLINE:
line loses its mark (`--OFFLINE: x = 1` -> `x = 1`, its indent kept).
"""
import re
import sys

OFFLINE_LINE = re.compile(r'^(\s*)(?:--|;|#)?\s*OFFLINE: ?(.*)$')


def edition(text, mode):
    out, skipping, n_blocks, n_off = [], False, 0, 0
    for line in text.splitlines(keepends=True):
        if 'ONLINE ONLY BEGIN' in line:
            assert not skipping, 'nested ONLINE ONLY BEGIN'
            skipping = mode == 'offline'
            n_blocks += 1
            continue
        if 'ONLINE ONLY END' in line:
            skipping = False
            continue
        if skipping:
            continue
        m = OFFLINE_LINE.match(line.rstrip('\r\n'))
        if m:
            n_off += 1
            if mode == 'offline':
                end = line[len(line.rstrip('\r\n')):]
                out.append(m.group(1) + m.group(2) + end)
            continue
        out.append(line)
    assert not skipping, 'ONLINE ONLY BEGIN without END'
    return ''.join(out), n_blocks, n_off


if __name__ == '__main__':
    mode, files = sys.argv[1], sys.argv[2:]
    assert mode in ('online', 'offline'), mode
    for p in files:
        with open(p, encoding='utf-8', newline='') as f:
            s = f.read()
        s, nb, no = edition(s, mode)
        with open(p, 'w', encoding='utf-8', newline='') as f:
            f.write(s)
        print(f'{mode}: {p}: {nb} online-only blocks, {no} offline lines')
