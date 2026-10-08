import json, re, numpy as np
d=json.load(open('intent_export.json')); R=json.load(open('rows.json'))
T=R['turns']
def arm(r): return 'on' if 'intent-on' in r['run']['notes'] else 'off'
for a in ('off','on'):
    ic=[c for r in d if arm(r)==a for c in r['calls'] if c['purpose']=='intent']
    gm=[c for r in d if arm(r)==a for c in r['calls'] if c['purpose']=='gm']
    st=[c['latency_ms'] for r in d if arm(r)==a for c in r['calls'] if c['purpose']=='turn.intent' and (c.get('meta') or {}).get('label')]
    err=[c for r in d if arm(r)==a for c in r['calls'] if c['status']!='ok']
    nt=sum(1 for t in T if t['arm']==a)
    print(a, 'intent calls', len(ic), 'cost', sum(c['cost_micro_usd'] or 0 for c in ic)/1e6, 'per call', np.mean([c['cost_micro_usd'] or 0 for c in ic])/1e6 if ic else 0, 'per turn', sum(c['cost_micro_usd'] or 0 for c in ic)/1e6/nt)
    print('   gm calls', len(gm), 'gm cost per turn', sum(c['cost_micro_usd'] or 0 for c in gm)/1e6/nt, 'gm latency median', np.median([c['latency_ms'] for c in gm if c['status']=='ok']))
    if st: print('   intent step (LLM) median', np.median(st)/1000, 'p90', np.percentile(st,90)/1000)
    print('   non-ok calls', len(err), sorted({(c['purpose'],c['status']) for c in err}))
    cs=[t['conf'] for t in T if t['arm']==a and t['conf'] is not None]
    print('   conf values', {v: cs.count(v) for v in sorted(set(cs))})
def echo(p,g,n=8):
    pw=re.findall(r"[a-z']+",(p or '').lower()); gw=' '+' '.join(re.findall(r"[a-z']+",(g or '').lower()))+' '
    return any(' '+' '.join(pw[i:i+n])+' ' in gw for i in range(len(pw)-n+1))
for a in ('off','on'):
    for u in ('quote','summary'):
        X=[t for t in T if t['arm']==a and t['used']==u]
        if X: print(a,u,'n',len(X),'8-word echo', sum(echo(t['player'],t['gm']) for t in X), '6-word', sum(echo(t['player'],t['gm'],6) for t in X))
print('--- ronny on, quoted inputs')
for t in T:
    if t['arm']=='on' and t['persona']=='ronny' and t['used']=='quote': print(t['run'], t['n'], t['conf'], '|', t['player'][:170].replace('\n',' '))
