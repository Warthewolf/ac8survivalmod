"""Replay a run's income on proposed economy rules (income only; spending as it happened is reported separately).

Rules replayed:
  share(N)   a teammate's kill pays min(0.5, 1/(N-1)) of a kill (N players); your own pays x1
  joiners    a kill credited "by you" on a joiner although they fired nothing in the 6 s before it is a teammate's
  specials   every special reward x 1/sqrt(N)
  spaceport  each fleet line pays one ship (its smallest observed unit), not one per part
  airstrike  airstrike kills x0.25 (was x0.5)
Usage: python3 -I replay.py label=role:path ...
"""
import math
import re
import sys
from collections import defaultdict

R_ROUND = re.compile(r"hud: callout '(?:SPECIAL )?ROUND (\d+)'")
R_STATS = re.compile(r'stats: round (\d+) \(.*?(\d+) players\)')
R_KILL = re.compile(r'kill: \S+; you were ([\d.]+) km away.*?(you fired nothing seen|you fired)')
R_CRED = re.compile(r'credits: \+(\d+) \((.*)\), now (-?\d+)$')
UNIT = {'aegis': 2400, 'ford': 9000, 'wasp': 3600, 'boat': 900}


def share(n):
    return 0.5 if n <= 2 else min(0.5, 1.0 / (n - 1))


def replay(label, role, path):
    lines = open(path, encoding='utf-8', errors='replace').read().splitlines()
    # players per round, from the stats lines (a run restarted at round 1 resets nothing here: the last run wins)
    players = {}
    for ln in lines:
        m = R_STATS.search(ln)
        if m:
            players[int(m.group(1))] = int(m.group(2))
    rnd, last_n, pend = 0, 2, None
    old, new = defaultdict(float), defaultdict(float)
    per_round = defaultdict(lambda: [0.0, 0.0])
    runs = 0
    for ln in lines:
        m = R_ROUND.search(ln)
        if m:
            r = int(m.group(1))
            if r == 1 or r < rnd:
                runs += 1
                old.clear(); new.clear(); per_round.clear()
            rnd = r
            continue
        m = R_KILL.search(ln)
        if m:
            pend = (float(m.group(1)), m.group(2) == 'you fired nothing seen')
            continue
        m = R_CRED.search(ln)
        if not m:
            continue
        amt, text = int(m.group(1)), m.group(2)
        n = players.get(rnd, last_n)
        last_n = n
        if 'cleared' in text:
            k, v = 'round clears', amt
        elif ' down (' in text and re.search(r'\((fighter|bomber|heavy)', text):
            by = re.search(r'by (\w+) x[\d.]+', text)
            by = by.group(1) if by else 'you'
            if by == 'airstrike':
                k, v = 'airstrike kills', amt * 0.5
            elif by == 'wingmate':
                k, v = 'teammates\' kills', amt / 0.5 * share(n)
            elif by == 'you':
                if role == 'join' and pend and pend[1]:
                    k, v = 'teammates\' kills', amt * share(n)
                else:
                    k, v = 'own kills', amt
            else:
                k, v = 'allies/ships/defences kills', amt
            pend = None
        else:
            v = amt
            mm = re.search(r"spaceport's fleet: (\w+) sunk", text)
            if mm and mm.group(1) in UNIT:
                v = UNIT[mm.group(1)]
            k, v = 'specials', v / math.sqrt(max(1, n))
        old[k] += amt
        new[k] += v
        per_round[rnd][0] += amt
        per_round[rnd][1] += v
    return old, new, per_round


if __name__ == '__main__':
    for a in sys.argv[1:]:
        label, rest = a.split('=', 1)
        role, path = rest.split(':', 1)
        old, new, pr = replay(label, role, path)
        to, tn = sum(old.values()), sum(new.values())
        print('%-12s %-4s income now %8d -> proposed %8d (%3.0f%%)' % (label, role, to, tn, 100 * tn / max(1, to)))
        for k in sorted(old, key=lambda k: -old[k]):
            print('    %-30s %8d -> %8d' % (k, old[k], new[k]))
        cum_o = cum_n = 0
        marks = []
        for r in sorted(pr):
            cum_o += pr[r][0]; cum_n += pr[r][1]
            if r in (5, 10, 15, 20, 25, 30, 35, 40, 45) or r == max(pr):
                marks.append('r%d %dk->%dk' % (r, cum_o // 1000, cum_n // 1000))
        print('    earned by round: ' + ', '.join(marks))
