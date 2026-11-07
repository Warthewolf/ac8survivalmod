"""Economy pass over Survival Lua logs: per run, what came in (by source), what went out (by item), balances.

Usage: python3 -I econ.py label=path/to/AC8SurvivalMode_lua.log ... [--json out.json]
"""
import json
import re
import sys
from collections import defaultdict

CAT = {
    'Rearm': 'ammo', 'Missiles': 'ammo', 'Special': 'ammo', 'Flares': 'ammo',
    'RepairAircraft': 'repair', 'RepairAirfield': 'repair',
    'UpAirframe': 'upgrades', 'UpGun': 'upgrades', 'UpFlares': 'upgrades', 'UpBays': 'upgrades',
    'Airstrike': 'tactical', 'Ecm': 'tactical', 'Decoy': 'tactical', 'Insurance': 'tactical',
    'Wingmen': 'allies', 'Moonchild': 'allies', 'ShipAegis': 'allies', 'VoidWatcher': 'allies',
    'AAGun': 'defences', 'SAM': 'defences', 'Ciws': 'defences',
}

R_CREDIT = re.compile(r'^(\d\d:\d\d:\d\d) credits: \+(\d+) \((.*)\), now (-?\d+)$')
R_ROUND = re.compile(r"^(\d\d:\d\d:\d\d) hud: callout '(?:SPECIAL )?ROUND (\d+)'")
R_SHOP = re.compile(r'^(\d\d:\d\d:\d\d) shop: (\w+): (.*?) for (\d+)[\. (]')
R_ASK = re.compile(r'^(\d\d:\d\d:\d\d) shop: asked the host to build (\w+) \((\d+) paid')
R_REFUND = re.compile(r'^(\d\d:\d\d:\d\d) shop: (\w+): .*?; (\d+) refunded')
R_REFUND2 = re.compile(r'^(\d\d:\d\d:\d\d) shop: .*refunded (\d+)')
R_REVASK = re.compile(r'^(\d\d:\d\d:\d\d) revive: asked the host to revive player \d+ for (\d+)')
R_REVHOST = re.compile(r'^(\d\d:\d\d:\d\d) revive: player (\d+) revived player \d+ for (\d+)')
R_NOTENOUGH = re.compile(r'^(\d\d:\d\d:\d\d) shop: (\w+): NOT ENOUGH ZOLLARS \((\d+) needed\)')
R_SLOT = re.compile(r'coop: open=1;.*role=(\w+);state=linked;slot=(-?\d+);players=(\d+)')
R_STATS = re.compile(r'stats: round (\d+) \(.*?(\d+) players\)')
R_START = re.compile(r'run: .*starts over too: (\d+) zollars')
R_END = re.compile(r'left Survival.s level in round (\d+) with (-?\d+) zollars')


def income_x(text):
    m = re.search(r'income x([\d.]+)', text)
    return float(m.group(1)) if m else 1.0


def source(text):
    if 'cleared' in text:
        return 'round clear'
    m = re.search(r'by (wingmate|allies|ships|defences|airstrike|airstrike)', text)
    if ' down (' in text:
        return 'kills: ' + (m.group(1) if m else 'you')
    return 'special/other'


def parse(label, path):
    runs, cur = [], None
    slot = None
    role = None
    last_round = None

    def new_run(t, why):
        nonlocal cur
        cur = dict(label=label, start=t, why=why, rounds=defaultdict(lambda: dict(earn=defaultdict(int), spend=defaultdict(int),
                   bal=None, notenough=[])), first_round=None, last_round=None, players=set(), income_x=set(),
                   start_bal=None, end_bal=None, role=role)
        runs.append(cur)

    for line in open(path, encoding='utf-8', errors='replace'):
        line = line.rstrip('\n')
        m = R_SLOT.search(line)
        if m:
            role, slot = m.group(1), int(m.group(2))
        m = R_ROUND.match(line)
        if m:
            r = int(m.group(2))
            if cur is None or (r == 1) or (cur['last_round'] and r < cur['last_round']):
                new_run(m.group(1), 'round %d callout' % r)
            cur['last_round'] = r
            if cur['first_round'] is None:
                cur['first_round'] = r
            last_round = r
            continue
        if cur is None:
            m = R_CREDIT.match(line)
            if not m:
                continue
            new_run(m.group(1), 'first credit')
        rd = cur['rounds'][cur['last_round'] or 0]
        m = R_START.search(line)
        if m:
            cur['start_bal'] = int(m.group(1))
        m = R_STATS.search(line)
        if m:
            cur['players'].add(int(m.group(2)))
        m = R_CREDIT.match(line)
        if m:
            amt, text, now = int(m.group(2)), m.group(3), int(m.group(4))
            rd['earn'][source(text)] += amt
            rd['bal'] = now
            cur['income_x'].add(income_x(text))
            if cur['start_bal'] is None:
                cur['start_bal'] = now - amt
            continue
        m = R_NOTENOUGH.match(line)
        if m:
            rd['notenough'].append((m.group(2), int(m.group(3))))
            continue
        m = R_ASK.match(line)
        if m:
            rd['spend'][CAT.get(m.group(2), m.group(2))] += int(m.group(3))
            continue
        m = R_REFUND.match(line)
        if m:
            rd['spend'][CAT.get(m.group(2), m.group(2))] -= int(m.group(3))
            continue
        m = R_REVASK.match(line)
        if m:
            rd['spend']['revives'] += int(m.group(2))
            continue
        m = R_REVHOST.match(line)
        if m and slot is not None and int(m.group(2)) == slot + 1 and role == 'host':
            rd['spend']['revives'] += int(m.group(3))
            continue
        if 'the host built your' in line or 'built for player' in line or 'NOT ENOUGH' in line:
            continue
        m = R_SHOP.match(line)
        if m and m.group(2) in CAT:
            rd['spend'][CAT[m.group(2)]] += int(m.group(4))
            continue
        m = R_END.search(line)
        if m:
            cur['end_bal'] = int(m.group(2))
    return runs


def summary(runs):
    out = []
    for r in runs:
        earn, spend = defaultdict(int), defaultdict(int)
        ne = []
        for rn, d in sorted(r['rounds'].items()):
            for k, v in d['earn'].items():
                earn[k] += v
            for k, v in d['spend'].items():
                spend[k] += v
            ne += [(rn,) + x for x in d['notenough']]
        bals = [(rn, d['bal']) for rn, d in sorted(r['rounds'].items()) if d['bal'] is not None]
        if not earn:
            continue
        out.append(dict(label=r['label'], role=r['role'], rounds='%s-%s' % (r['first_round'], r['last_round']),
                        players=sorted(r['players']), income_x=sorted(r['income_x']), start=r['start_bal'],
                        end=r['end_bal'] if r['end_bal'] is not None else (bals[-1][1] if bals else None),
                        earned=sum(earn.values()), spent=sum(spend.values()), earn=dict(earn), spend=dict(spend),
                        peak=max((b for _, b in bals), default=None), notenough=ne,
                        per_round=[(rn, sum(d['earn'].values()), sum(d['spend'].values()), d['bal'])
                                   for rn, d in sorted(r['rounds'].items())]))
    return out


if __name__ == '__main__':
    args = [a for a in sys.argv[1:] if '=' in a]
    allruns = []
    for a in args:
        label, path = a.split('=', 1)
        allruns += summary(parse(label, path))
    if '--json' in sys.argv:
        json.dump(allruns, open(sys.argv[sys.argv.index('--json') + 1], 'w'), indent=1)
    for s in allruns:
        print('%-14s %-4s rounds %-6s players %-9s x%-12s start %-6s end %-7s peak %-7s earned %-7d spent %-7d' % (
            s['label'], s['role'], s['rounds'], s['players'], s['income_x'], s['start'], s['end'], s['peak'], s['earned'], s['spent']))
        print('    earn: ' + ', '.join('%s %d' % kv for kv in sorted(s['earn'].items(), key=lambda kv: -kv[1])))
        print('    spend: ' + ', '.join('%s %d' % kv for kv in sorted(s['spend'].items(), key=lambda kv: -kv[1])))
        if s['notenough']:
            print('    not enough: ' + ', '.join('r%d %s %d' % x for x in s['notenough']))
