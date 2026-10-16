"""Render light and dark variants of each screen.
Base sources: a*.html and c*.html are authored dark, b*.html light.
A theme = a colour map (single-pass hex/rgba substitution) + an extra stylesheet."""
import re, subprocess, os, sys
HERE=os.path.dirname(os.path.abspath(__file__))
OUT=os.path.join(HERE,'..','images'); BUILD=os.path.join(HERE,'build')
os.makedirs(OUT,exist_ok=True); os.makedirs(BUILD,exist_ok=True)

A_LIGHT={'#0f1218':'#f3f4f7','#131821':'#ffffff','#232a36':'#e2e5eb','#1e2532':'#eef1f6','#2b3445':'#d6dbe4',
'#7d8697':'#5f6778','#9aa3b5':'#525a6b','#e6e8ee':'#1c2230','#161c26':'#ffffff','#242c3a':'#e2e5eb','#252e3d':'#eef1f6',
'#33405a':'#cdd4df','#e8c27a':'#9a6410','#8a93a5':'#5f6778','#c8cfdb':'#363e4f','#3a4a63':'#cdd6e3','#1b2230':'#f2f4f8',
'#55667f':'#8a99b0','#232c3b':'#b4bfcf','#2a2f38':'#5a6272','#0f141c':'#f6f7fa','#121822':'#f8f9fb','#2a2416':'#fdf2dc',
'#2f6b4f':'#d6f0e1','#d8ffe9':'#1d6a43','#222a37':'#eceef3','#1f2a3a':'#e4ecfa','#8fb3e6':'#2d5ca6','#3a4456':'#c5ccd8',
'#5a4824':'#e5c98f','#dfe2e8':'#262c38','#1f3047':'#e5edfa','#2d4566':'#b9cdec','#9fb6d6':'#33598f','#1b1418':'#fdeeee',
'#5a2e33':'#efc0c0','#ff8c84':'#b02f27','#6fd39c':'#1b7d48','#6b7486':'#8a92a3','#24324a':'#e1e8f4','#c8d6f0':'#2d4876',
'#3a1c20':'#fbe2e2','#ffb3ad':'#a0281f','color:#fff':'color:#111827','#c48a2c':'#d9a441'}
A_LIGHT_CSS='.card{box-shadow:0 1px 2px rgba(20,30,50,.06),0 4px 14px rgba(20,30,50,.05)}'

B_DARK={'#3b2a1d':'#140d08','#5a4030':'#2e1f14','#2a1c12':'#080503'}
B_DARK_CSS='''
.paper{filter:sepia(.38) brightness(.88) saturate(1.1);box-shadow:0 22px 50px rgba(0,0,0,.85),0 0 0 1px rgba(0,0,0,.4)!important}
.felt{filter:brightness(.85)}
body::before{content:'';position:fixed;inset:0;pointer-events:none;z-index:0;background:radial-gradient(ellipse 55% 60% at 36% 30%,rgba(255,170,80,.22),rgba(0,0,0,0) 70%)}
body::after{content:'';position:fixed;inset:0;pointer-events:none;z-index:50;
 background:radial-gradient(ellipse 80% 90% at 36% 30%,rgba(255,190,110,.10) 0,rgba(255,170,90,.04) 38%,rgba(0,0,0,0) 58%,rgba(10,5,0,.40) 100%)}
'''
B_LIGHT_CSS='''body{background:#b48a5e;background-image:repeating-linear-gradient(91deg,rgba(90,55,25,.10) 0 2px,transparent 2px 13px),repeating-linear-gradient(89deg,rgba(255,240,215,.10) 0 3px,transparent 3px 29px),radial-gradient(ellipse at 35% 25%,#d2ab7c,#9c7246 90%)!important}
body::after{content:'';position:fixed;inset:0;pointer-events:none;z-index:50;background:linear-gradient(115deg,rgba(255,250,235,.10),rgba(255,250,235,0) 45%)}'''

C_LIGHT={'#e9e1cf':'#2a2620','#cfc7b5':'#3d372f','#b8b0a0':'#544c40','#8892a0':'#6a6357','#aab3c0':'#5a554c','#d9cfb8':'#3d372f',
'#d4b06a':'#8a6216','#f0e6cf':'#2a2620','#9aa4b2':'#6a6357','#b8c2d0':'#3e4652','#e8d29c':'#7a5310','#2a313c':'#ddd6c8',
'#4a5464':'#a89f8e','#232a34':'#e8e1d2','#cfc3a6':'#6a5a40','#8f887a':'#8a8172','#e9dcc0':'#4a3a1c','#c4574a':'#a83c30',
'#8fa6c4':'#40618d','#1b222c':'#c3ccd6','#11161d':'#aeb8c4','#c8d2de':'#ffffff','#e9eef5':'#ffffff','#2a3340':'#b9c3cf',
'rgba(10,13,18,.5)':'rgba(255,255,255,.55)','rgba(160,180,210,.08)':'rgba(60,80,110,.07)','rgba(160,180,210,.15)':'rgba(60,80,110,.18)',
'rgba(212,176,106,.06)':'rgba(190,150,70,.13)','rgba(212,176,106,.35)':'rgba(150,110,40,.40)','rgba(233,225,207,.06)':'rgba(255,255,255,.65)',
'rgba(233,225,207,.18)':'rgba(60,50,40,.22)','rgba(233,225,207,.15)':'rgba(60,50,40,.18)','rgba(233,225,207,.12)':'rgba(60,50,40,.14)',
'rgba(233,225,207,.08)':'rgba(60,50,40,.12)','rgba(212,176,106,.5)':'rgba(150,110,40,.5)'}
C_LIGHT_CSS='''body{background:radial-gradient(ellipse at 50% 0%,#f4f0e8 0,#e6e0d4 55%,#d3ccbe 100%)!important;color:#2a2620}
.rain{background-image:repeating-linear-gradient(104deg,rgba(60,70,90,.045) 0 1px,transparent 1px 9px)!important}
.vellum{box-shadow:0 18px 50px rgba(60,45,25,.28),0 0 0 1px rgba(60,45,25,.15)!important}
.mem{box-shadow:0 6px 16px rgba(60,45,25,.25)!important}
.cap{color:#2a2620!important}.wbtn{color:#fff8e8!important}'''
C_DARK_CSS='''body{background:radial-gradient(ellipse at 50% 40%,#2a2218 0,#15110d 45%,#07080a 100%)!important}
.rain{opacity:.6}
.vellum{filter:sepia(.18) brightness(.97);box-shadow:0 0 0 1px rgba(0,0,0,.4),0 30px 80px rgba(0,0,0,.8),0 0 140px rgba(255,160,70,.22)!important}
body::after{content:'';position:fixed;inset:0;pointer-events:none;z-index:50;background:radial-gradient(ellipse 60% 70% at 50% 48%,rgba(255,170,80,.07) 0,rgba(0,0,0,0) 55%,rgba(0,0,0,.35) 100%)}
.candle{position:absolute;z-index:40}'''
CANDLE='''<svg class="candle" style="{pos}" width="70" height="150" viewBox="0 0 70 150"><defs><radialGradient id="cg"><stop offset="0" stop-color="#ffd27a" stop-opacity=".55"/><stop offset="1" stop-color="#ff9a3a" stop-opacity="0"/></radialGradient></defs><circle cx="35" cy="34" r="34" fill="url(#cg)"/><path d="M35 14 Q44 30 35 44 Q26 30 35 14Z" fill="#ffd27a"/><path d="M35 24 Q39 33 35 41 Q31 33 35 24Z" fill="#fff4d0"/><rect x="34" y="42" width="2" height="6" fill="#2a1a0a"/><path d="M22 48 Q22 46 26 46 L44 46 Q48 46 48 48 L48 138 L22 138Z" fill="#e8dcc0"/><path d="M40 46 Q44 60 42 70 Q40 62 38 50Z" fill="#f6eedb"/><ellipse cx="35" cy="140" rx="30" ry="7" fill="#5a4630"/></svg>'''
CANDLE_POS={'c1':'left:1160px;top:815px','c2':'left:1500px;top:830px'}

def remap(s,m):
    if not m: return s
    keys=sorted(m,key=len,reverse=True)
    pat=re.compile('|'.join(re.escape(k) for k in keys),re.I)
    low={k.lower():v for k,v in m.items()}
    return pat.sub(lambda x:low[x.group(0).lower()],s)

THEMES={'a':{'dark':({},''),'light':(A_LIGHT,A_LIGHT_CSS)},
        'b':{'light':({},B_LIGHT_CSS),'dark':(B_DARK,B_DARK_CSS)},
        'c':{'dark':({},C_DARK_CSS),'light':(C_LIGHT,C_LIGHT_CSS)}}

def shot(html,png,w=1600,h=1000):
    subprocess.run(['google-chrome','--headless=new','--no-sandbox','--disable-gpu','--hide-scrollbars',
      '--force-device-scale-factor=1',f'--window-size={w},{h}',f'--screenshot={png}','file://'+html],
      stderr=subprocess.DEVNULL,stdout=subprocess.DEVNULL,check=True)

def build(name):
    d=name[0]; base=open(os.path.join(HERE,name+'.html')).read()
    for theme,(cmap,css) in THEMES[d].items():
        s=base.replace('href="a-common.css"','href="../a-common.css"').replace('href="b-common.css"','href="../b-common.css"').replace('href="c-common.css"','href="../c-common.css"')
        commons={'a':'a-common.css','b':'b-common.css','c':'c-common.css'}[d]
        common=open(os.path.join(HERE,commons)).read()
        s=s.replace(f'<link rel="stylesheet" href="../{commons}">',f'<style>{remap(common,cmap)}</style>')
        s=remap(s,cmap)
        s=s.replace('</head>',f'<style>{css}</style></head>')
        if d=='c' and theme=='dark': s=s.replace('</body>',CANDLE.format(pos=CANDLE_POS[name])+'</body>')
        f=os.path.join(BUILD,f'{name}-{theme}.html'); open(f,'w').write(s)
        shot(f,os.path.join(OUT,f'{name}-{theme}.png'))


def overviews():
    t=open(os.path.join(HERE,'overview.tmpl.html')).read()
    pal={'light':dict(bg='#f3f1ec',fg='#1f2128',mut='#5c616b',gold='#8a6216',bd='#d6d2c8'),
         'dark':dict(bg='#0d1015',fg='#e9e1cf',mut='#9aa4b2',gold='#d4b06a',bd='#2a313c')}
    for m,p in pal.items():
        f=os.path.join(HERE,f'overview-{m}.html'); open(f,'w').write(t.format(MODE=m.capitalize()+' mode',m=m,**p))
        shot(f,os.path.join(OUT,f'overview-{m}.png'),2520,1360)

if __name__=='__main__':
    for n in (sys.argv[1:] or ['a1','a2','b1','b2','c1','c2']): build(n)
    overviews()
