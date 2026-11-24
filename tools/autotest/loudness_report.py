"""loudness_report.py : the speakers' levels (tools/autotest/loudness.ps1) matched to a run's "SOUND ..." lines (2026-11-24).
    python -I tools/autotest/loudness_report.py <loudness.txt> <run folder or its verdict.txt>
Each SOUND line's step: its loudest 100 ms and its mean in the 4 s after it, against the baseline's (the "SOUND quiet"
line). The game's clock (the second time on a verdict line) is the one loudness.ps1 writes.
"""
import os
import re
import sys


def levels(path):
    out = []
    for line in open(path, encoding='utf-8', errors='replace'):
        m = re.match(r'(\d\d):(\d\d):(\d\d)\.(\d\d\d) (-?[\d.]+)', line)
        if m:
            h, mi, s, ms, db = m.groups()
            out.append((int(h) * 3600 + int(mi) * 60 + int(s) + int(ms) / 1000.0, float(db)))
    return out


def steps(path):
    if os.path.isdir(path):
        path = os.path.join(path, 'verdict.txt')
    out = []
    for line in open(path, encoding='utf-8', errors='replace'):
        m = re.search(r' (\d\d):(\d\d):(\d\d) selftest: INFO (SOUND .*)$', line)
        if m:
            h, mi, s, what = m.groups()
            out.append((int(h) * 3600 + int(mi) * 60 + int(s), what.strip()))
    return out


def main(lpath, rpath):
    L, S = levels(lpath), steps(rpath)
    if not L or not S:
        print('loudness_report: %d levels, %d SOUND lines: nothing to match' % (len(L), len(S)))
        return 1
    def window(t0, t1):
        v = [db for t, db in L if t0 <= t < t1]
        if not v:
            return None, None
        p = [10 ** (db / 10) for db in v]
        import math
        return max(v), 10 * math.log10(sum(p) / len(p)) if sum(p) > 0 else -120
    base = None
    print('%-58s %8s %8s %8s' % ('step', 'peak', 'mean', 'vs base'))
    for t, what in S:
        pk, mean = window(t, t + 4)
        if pk is None:
            print('%-58s (no levels then)' % what[:58])
            continue
        if what.startswith('SOUND quiet'):
            base = mean
        rel = '' if base is None else '%+7.1f' % (mean - base)
        print('%-58s %8.1f %8.1f %8s' % (what[:58], pk, mean, rel))
    return 0


if __name__ == '__main__':
    sys.exit(main(sys.argv[1], sys.argv[2]))
