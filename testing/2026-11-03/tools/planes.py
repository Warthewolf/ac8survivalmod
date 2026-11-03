import re,sys,collections
L,C=sys.argv[1],sys.argv[2]
gen={} ; cur={}   # unit -> current gen
P=collections.OrderedDict()
ev=[]
for line in open(C,encoding='utf-8',errors='replace'):
    t=line[:12]
    m=re.search(r"the host's (\S+) spawned here \(gen (\d+)\)",line)
    if m: ev.append((t[:8],'S',m.group(1),int(m.group(2))))
    m=re.search(r"copy \S+ \S+\.(\S+_C_\d+) taken down \(id (\d+)(, forced)?",line)
    if m: ev.append((t[:8],'T',m.group(1),m.group(2)+(' F' if m.group(3) else '')))
for line in open(L,encoding='utf-8',errors='replace'):
    t=line[:8]
    m=re.search(r"AI aircraft created #\d+: (\S+) \((\S+), k (\d+)\)",line)
    if m: ev.append((t,'C',m.group(1),m.group(2)))
    m=re.search(r"round probe: (\S+) down",line)
    if m: ev.append((t,'D',m.group(1),''))
    m=re.search(r"kills: (\S+) \(\S+\) went down to the (\w+)",line)
    if m: ev.append((t,'K',m.group(1),m.group(2)))
    m=re.search(r"kill-time: (\S+) \(.*?\): .*; by (.*)$",line)
    if m: ev.append((t,'B',m.group(1),m.group(2).strip()))
ev.sort(key=lambda e:e[0])
for t,k,a,b in ev:
    if k=='S': cur[a]=b
    elif k=='C':
        P[a]=dict(unit=b,gen=cur.get(b),created=t)
    elif a in P:
        d=P[a]
        if k=='D': d.setdefault('down',t)
        elif k=='K': d['to']=b
        elif k=='B': d['by']=b
        elif k=='T': d.setdefault('taken',t+' '+b)
want=[tuple(x.split(':')) for x in sys.argv[3:]]
for name,d in P.items():
    if any(d['unit']==u and str(d['gen'])==g for u,g in want) or not want:
        print(name, d)
