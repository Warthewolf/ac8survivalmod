import re,sys
# pair each "kill:" line (distance, fired) with the next "credits:" line for that kill
for arg in sys.argv[1:]:
    label,path=arg.split('=',1)
    tot=dict(n=0,amt=0); idle=dict(n=0,amt=0); far_idle=dict(n=0,amt=0); wing=dict(n=0,amt=0)
    pend=None
    for line in open(path,encoding='utf-8',errors='replace'):
        m=re.search(r'kill: \S+; you were ([\d.]+) km away.*?(you fired nothing seen|you fired)',line)
        if m: pend=(float(m.group(1)), m.group(2)=='you fired nothing seen'); continue
        m=re.search(r'credits: \+(\d+) \((\w+) down \((fighter|bomber|heavy)[^)]*?(, by (\w+) x[\d.]+)?\)',line)
        if m and pend:
            amt=int(m.group(1)); by=m.group(5) or 'you'
            if by=='you':
                tot['n']+=1; tot['amt']+=amt
                if pend[1]: idle['n']+=1; idle['amt']+=amt
                if pend[1] and pend[0]>3: far_idle['n']+=1; far_idle['amt']+=amt
            elif by=='wingmate': wing['n']+=1; wing['amt']+=amt
            pend=None
    if tot['n']:
        print(f"{label:12s} 'by you' kills {tot['n']:4d} ({tot['amt']:7d} Z); of them fired nothing seen in 6 s: {idle['n']:4d} ({idle['amt']:7d} Z, {100*idle['amt']/tot['amt']:.0f}%), and >3 km away too: {far_idle['n']:4d} ({100*far_idle['amt']/tot['amt']:.0f}%); 'by wingmate' {wing['n']} ({wing['amt']} Z)")
