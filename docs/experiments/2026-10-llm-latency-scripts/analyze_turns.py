import csv,collections,statistics as st,datetime as dt
rows=[r for r in csv.reader(open('turns.tsv'),delimiter='\t') if len(r)==14 and r[0]!='game_session_id']
def t(s): return dt.datetime.strptime(s,'%H:%M:%S.%f') if s else None
turns=collections.defaultdict(list)
for r in rows: turns[(r[0],int(r[1] or 0))].append(r)
out=[]
for (sid,n),rs in turns.items():
  d={r[2]:r for r in rs if r[3]=='function'}
  if 'turn.gm' not in d or 'turn.persist' not in d or 'turn.intent' not in d: continue
  gm=[r for r in rs if r[2]=='gm' and r[3]=='llm']
  npc=[r for r in rs if r[2]=='npc_reaction']
  intent=[r for r in rs if r[2]=='intent']
  lat=lambda p:int(d[p][6]) if p in d else 0
  start=t(d['turn.intent'][12]); end=t(d['turn.persist'][12])+dt.timedelta(milliseconds=lat('turn.persist'))
  wall=(end-start).total_seconds()*1000
  rules_start=t(d['turn.rules'][12]) if 'turn.rules' in d else None
  gap=(rules_start-start).total_seconds()*1000-lat('turn.intent') if rules_start else 0
  g=gm[0] if gm else None
  out.append(dict(session=sid,turn=n,start=d['turn.intent'][12],wall_ms=round(wall),intent_ms=lat('turn.intent'),handoff_ms=round(gap),
    rules_ms=lat('turn.rules'),npc_ms=lat('turn.npc_reactions'),premise_ms=lat('turn.premise_check'),prompt_ms=lat('turn.prompt'),
    gm_step_ms=lat('turn.gm'),gm_llm_ms=int(g[6]) if g else 0,gm_ttft_ms=int(g[7]) if g and g[7] else '',gm_in=g[8] if g else '',gm_out=g[9] if g else '',gm_cached=g[10] if g else '',
    gm_calls=len(gm),persist_ms=lat('turn.persist'),npc_calls=len(npc),npc_max_ms=max([int(x[6]) for x in npc],default=0),npc_sum_ms=sum(int(x[6]) for x in npc),intent_calls=len(intent),
    other=';'.join(sorted(set(r[2] for r in rs if r[3]!='function' and r[2] not in('gm','npc_reaction','intent'))))))
out.sort(key=lambda x:x['start'])
w=csv.DictWriter(open('turns_split.csv','w'),fieldnames=list(out[0].keys())); w.writeheader(); w.writerows(out)
def q(v,p): v=sorted(v); return v[min(len(v)-1,int(round(p*(len(v)-1))))]
for name,sel in [('gentry',[o for o in out if o['session'].startswith('643b8031')]),('all_today',out)]:
  print(name,'n=',len(sel))
  for k in ['wall_ms','intent_ms','handoff_ms','rules_ms','npc_ms','premise_ms','prompt_ms','gm_step_ms','gm_llm_ms','gm_ttft_ms','persist_ms','gm_out','gm_in','gm_cached','npc_calls','gm_calls']:
    v=[float(o[k]) for o in sel if o[k]!='']
    print(f"  {k:12} med={st.median(v):8.0f} p90={q(v,0.9):8.0f} min={min(v):6.0f} max={max(v):6.0f}")
  print('  gm share of wall', round(sum(o['gm_step_ms'] for o in sel)/sum(o['wall_ms'] for o in sel),3))
  print('  npc parallel check (step vs sum vs max) multi:',[(o['npc_ms'],o['npc_sum_ms'],o['npc_max_ms']) for o in sel if o['npc_calls']>1][:6])
for o in out:
  if o['session'].startswith('643b8031'): print(o['turn'],o['start'],o['wall_ms'],o['gm_llm_ms'],o['gm_ttft_ms'],o['gm_out'],o['gm_cached'],o['other'])
