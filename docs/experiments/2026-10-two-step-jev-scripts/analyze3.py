import json,collections,statistics as st,glob
rows=[json.loads(l) for l in open('runs.jsonl')]
def q(xs,p):
  xs=sorted(xs); k=(len(xs)-1)*p; f=int(k); c=min(f+1,len(xs)-1); return xs[f]+(xs[c]-xs[f])*(k-f)
K=collections.defaultdict(list)
for r in rows:
  for c in r['calls']: K[c['kind']].append(c)
for k,v in K.items():
  print(k,len(v),'in',round(st.mean(c['in'] for c in v)),'out',round(st.mean(c['out'] or 0 for c in v)),'bytes',round(st.mean(c['bytes'] for c in v)),'cost %.6f'%st.mean(c['cost'] for c in v),'p50',round(q([c['ms'] for c in v],.5)),'p90',round(q([c['ms'] for c in v],.9)))
A=collections.defaultdict(list)
for r in rows: A[r['arm']].append(r)
for a,v in A.items():
  sp=[r for r in v if len(r['calls'])>1]
  print(a,'turns',len(v),'speech turns',len(sp),'cost/turn %.6f'%st.mean(sum(c['cost'] for c in r['calls']) for r in v),
   'in/turn',round(st.mean(sum(c['in'] for c in r['calls']) for r in v)),
   'wall p50',round(q([r['wall_ms'] for r in v],.5)),'p90',round(q([r['wall_ms'] for r in v],.9)),
   '| speech-turn cost %.6f'%(st.mean(sum(c['cost'] for c in r['calls']) for r in sp) if sp else 0),
   'wall p50',round(q([r['wall_ms'] for r in sp],.5)) if sp else '-','p90',round(q([r['wall_ms'] for r in sp],.9)) if sp else '-')
# total spend all files
tot=0;n=0
for f in ['smoke.jsonl','runs.jsonl']:
  for l in open(f):
    r=json.loads(l)
    for c in r['calls']:
      if c['ok']: tot+=c['cost'] or 0; n+=1
print('spend',tot,'calls',n)
# check cost vs input tokens
c=K['listener'][0]; print('cost per in-token', c['cost']/c['in']*1e6)
