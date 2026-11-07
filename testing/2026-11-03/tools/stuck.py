import re,sys,collections,runpy
L,C=sys.argv[1],sys.argv[2]
sys.argv=[sys.argv[0],L,C,'NONE:0']
import io,contextlib
g=runpy.run_path(sys.argv[0].replace('stuck.py','planes.py'))
P=g['P']
# flights (unit,gen) -> planes
F=collections.defaultdict(list)
for n,d in P.items(): F[(d['unit'],d['gen'])].append(d)
stuck=set()
for line in open(L,encoding='utf-8',errors='replace'):
    m=re.search(r"coop: (\S+) is up here \(1 alive; its last flight here, gen (\d+)\)",line)
    if m: stuck.add((m.group(1),int(m.group(2))))
def secs(t): h,m,s=map(int,t.split(':')); return h*3600+m*60+s
rows=collections.Counter()
for (u,gn),ps in F.items():
    local=[p for p in ps if p.get('to') in ('ships','defences','allies')]
    lag=[secs(p['taken'][:8])-secs(p['down']) for p in local if 'taken' in p and 'down' in p]
    kind=tuple(sorted(set(p.get('to') for p in local)))
    rows[(kind,(u,gn) in stuck)]+=1
    if local: print(u,gn,'stuck' if (u,gn) in stuck else 'ok', [p.get('to') for p in local], 'lag',lag)
print(rows)
