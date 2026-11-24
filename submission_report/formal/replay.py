import csv
from check_model import make
rows=[l.rstrip('\r\n').split('\t') for l in open('trace_table.txt') if l.strip()]
hdr=rows[0]; import re; cols=[i for i,h in enumerate(hdr) if re.fullmatch(r'S\d+',h)]
d={r[0]:[r[i] for i in cols] for r in rows[1:]}
names={'IDLE':0,'CPU':1,'SCR':2,'INJ':3}
b=lambda x:x=='TRUE'
step=make(4,'aging')
n=len(cols); ok=True
for k in range(n-1):
    s=(names[d['state'][k]],int(d['left'][k]),b(d['cpu_req'][k]),b(d['scr_req'][k]),b(d['inj_req'][k]),int(d['scr_cnt'][k]),int(d['inj_cnt'][k]))
    t=(names[d['state'][k+1]],int(d['left'][k+1]),b(d['cpu_req'][k+1]),b(d['scr_req'][k+1]),b(d['inj_req'][k+1]),int(d['scr_cnt'][k+1]),int(d['inj_cnt'][k+1]))
    outs,fl=step(s,int(d['dur'][k]),None)
    good = t in outs
    ok&=good
    print(f"S{k+1}->S{k+2}", 'ok' if good else 'MISMATCH', s, t)
print('cpu_ready ever true:',any(b(x) for x in d['cpu_ready']), '| cpu_req in all steps from S3:', all(b(x) for x in d['cpu_req'][2:]))
print('replay consistent:',ok)
