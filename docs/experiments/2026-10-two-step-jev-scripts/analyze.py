import json,collections,statistics as st
rows=[json.loads(l) for l in open('runs.jsonl')]
L={l['id']:l for l in json.load(open('lines.json'))['lines']}
def truth(l):
  t=l['text']; i=l['id']
  if t.startswith('I look'): return {'other'}
  if t.startswith('I walk'): return {'physical'}
  if t.startswith('I stretch'): return {'other','physical'}
  if 'what work' in t: return {'speak'}
  if 'how much did you give' in t: return {'speak'}
  if i=='6d938a30-13': return {'speak'}
  if t in('Yes.','No, thank you.'): return {'speak','trade'}
  return {'trade'}
M={'speak':'speak','observe':'other','freeform':'other','wait':'other','rest':'other','train':'other','other':'other',
   'buy':'trade','sell':'trade','trade':'trade','spend':'trade','ask_price':'trade'}
cls=lambda a: M.get(a,'physical')
def q(xs,p):
  xs=sorted(xs); k=(len(xs)-1)*p; f=int(k); c=min(f+1,len(xs)-1); return xs[f]+(xs[c]-xs[f])*(k-f)
res={}
# stored
st_ok=sum(cls(l['stored']['action']) in truth(l) for l in L.values())
print('stored single acc',st_ok,'/',len(L))
s1=[(r['id'],r['round'],r['calls'][0]) for r in rows if r['arm']!='single']
s1ok=sum(c['reply']['act_class'] in truth(L[i]) for i,_,c in s1)
print('step1 acc',s1ok,'/',len(s1))
live=[(r['id'],r['calls'][0]) for r in rows if r['arm']=='single']
lok=sum(cls(c['reply']['action']) in truth(L[i]) for i,c in live)
print('live single (main) acc',lok,'/',len(live))
confs=[c['reply']['confidence']['act_class'] for _,_,c in s1]
print('step1 conf quantiles', [round(q(confs,p),2) for p in (0,.1,.25,.5,.75,.9,1)], 'n',len(confs))
bins=collections.Counter(min(int(c*10),9) for c in confs); print('hist',[(f"{b/10:.1f}-{(b+1)/10:.1f}",bins[b]) for b in range(10)])
print('voice',collections.Counter(c['reply']['voice'] for _,_,c in s1))
# per-line step1 majority
per=collections.defaultdict(list)
for i,_,c in s1: per[i].append((c['reply']['act_class'],c['reply']['confidence']['act_class'],c['reply']['voice']))
livep=collections.defaultdict(list)
for i,c in live: livep[i].append(c['reply']['action'])
print('\nDISAGREE stored vs step1 / wrong')
for i,l in L.items():
  labs=collections.Counter(x[0] for x in per[i]); top=labs.most_common(1)[0][0]
  sc=cls(l['stored']['action']); flag = sc!=top or any(x[0]!=top for x in per[i]) or sc not in truth(l) or top not in truth(l)
  if flag: print(i,repr(l['text']),'stored',l['stored']['action'],'->',sc,'| step1',dict(labs),'conf',[round(x[1],2) for x in per[i]],'| live main',collections.Counter(livep[i]),'| truth',truth(l))
json.dump({'per':per,'livep':livep},open('step1.json','w'))
