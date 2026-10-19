import json,collections,statistics as st
rows=[json.loads(l) for l in open('runs.jsonl')]
L={l['id']:l for l in json.load(open('lines.json'))['lines']}
per=collections.defaultdict(list)
for r in rows:
  if r['arm']!='single': c=r['calls'][0]['reply']; per[r['id']].append((c['act_class'],round(c['confidence']['act_class'],2),c['voice']))
print('LOW CONF (<0.8)')
for i,v in per.items():
  if any(x[1]<0.8 for x in v): print(i,repr(L[i]['text']),v)
print('VOICE none on trade/speak lines')
for i,v in per.items():
  n=sum(1 for x in v if x[2]=='none' and x[0] in('speak','trade'))
  if n: print(i,repr(L[i]['text']),f"{n}/4 none")
# step2
R=collections.defaultdict(lambda: collections.defaultdict(list))
for r in rows:
  if r['arm']=='1+3':
    for c in r['calls'][1:]:
      x=c['reply']; R[r['id']][c['npc']].append((x['social_act'],x['meaning'],x['tone'],round(x['confidence']['social_act'],2)))
print('\nSTEP2 per line (rounds 1,2): innkeep | smith | prospector')
diff=same=0; stab=collections.Counter(); tone=collections.Counter()
for i in L:
  if i not in R: continue
  b,h,p=R[i]['innkeep'],R[i]['smith'],R[i]['prospector']
  print(i,repr(L[i]['text'])[:42].ljust(42),'B',b,'| H',h,'| C',p)
  for n,v in (('B',b),('H',h),('C',p)):
    if len(v)==2: stab[n,'same' if v[0][:2]==v[1][:2] else 'diff']+=1
    for x in v: tone[n,x[2]]+=1
  if b and h:
    if b[0][:2]==h[0][:2]: same+=1
    else: diff+=1
print('B vs H (round-1 first sample) same act+meaning',same,'differ',diff)
print('stability',dict(stab)); print('tone',dict(tone))
