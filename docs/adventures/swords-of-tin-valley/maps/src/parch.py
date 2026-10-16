"""Parchment-style map helpers for "Swords of Tin Valley".

Render: run `python3 region.py`, `python3 valley.py` and `python3 village.py`
from this folder. Each writes its PNG one folder up (maps/).
Needs: matplotlib, numpy, scipy. Fonts (Google Fonts, OFL): IM Fell English SC,
IM Fell French Canon, Cinzel. Set FONT_DIR if they live elsewhere.
"""
import os
import numpy as np, matplotlib
matplotlib.use("Agg")
import matplotlib.pyplot as plt
from matplotlib import font_manager as fm, patheffects as pe
from scipy.ndimage import gaussian_filter
from scipy.interpolate import interp1d

G=os.environ.get("FONT_DIR","/usr/share/fonts/truetype/sand-box/google/")
for f in ["IM Fell English SC/IMFellEnglishSC-Regular.ttf","IM Fell French Canon/IMFellFrenchCanon-Regular.ttf",
          "IM Fell French Canon/IMFellFrenchCanon-Italic.ttf","Cinzel Decorative/CinzelDecorative-Bold.ttf","Cinzel/Cinzel-VariableFont_wght.ttf"]:
    fm.fontManager.addfont(G+f)
SC="IM Fell English SC"; CANON="IM Fell French Canon"; DECO="Cinzel"
INK=(0.23,0.15,0.08); RED=(0.55,0.12,0.08); PAPER=(0.93,0.86,0.70)
rng=np.random.default_rng(7)

def canvas(W=15,H=11,seed=7):
    global rng; rng=np.random.default_rng(seed)
    fig=plt.figure(figsize=(W,H),dpi=200); ax=fig.add_axes([0,0,1,1])
    ax.set_xlim(0,W*10); ax.set_ylim(0,H*10); ax.axis("off")
    n=600; m=int(n*H/W)
    noise=gaussian_filter(rng.normal(size=(m,n)),3)*0.6+gaussian_filter(rng.normal(size=(m,n)),25)*6
    noise=(noise-noise.mean())/noise.std()
    yy,xx=np.mgrid[0:m,0:n]; d=np.minimum.reduce([xx,n-xx,yy*n/m,(m-yy)*n/m])/n
    edge=np.clip(1-d/0.12,0,1)**2
    base=np.array(PAPER)[None,None,:]
    img=base*(1-0.035*noise[...,None])-edge[...,None]*np.array([0.30,0.33,0.36])
    for _ in range(5):  # stains
        cx,cy,r=rng.uniform(0,n),rng.uniform(0,m),rng.uniform(20,70)
        dd=np.hypot(xx-cx,yy-cy); ring=np.exp(-((dd-r)/3)**2)*0.05+np.exp(-(dd/r)**2)*0.02
        img-=ring[...,None]*np.array([0.5,0.6,0.8])
    ax.imshow(np.clip(img,0,1),extent=[0,W*10,0,H*10],zorder=0,interpolation="bicubic")
    return fig,ax

def wobble(pts,amp=0.4,step=0.8,smooth=4):
    pts=np.asarray(pts,float); seg=np.r_[0,np.cumsum(np.hypot(*np.diff(pts,axis=0).T))]
    if len(pts)>2:
        fx=interp1d(seg,pts[:,0],kind="quadratic"); fy=interp1d(seg,pts[:,1],kind="quadratic")
    else:
        fx=interp1d(seg,pts[:,0]); fy=interp1d(seg,pts[:,1])
    t=np.linspace(0,seg[-1],max(int(seg[-1]/step),4)); x,y=fx(t),fy(t)
    dx,dy=np.gradient(x),np.gradient(y); L=np.hypot(dx,dy)+1e-9
    nz=gaussian_filter(rng.normal(size=len(t)),smooth)*amp*3
    return x-dy/L*nz, y+dx/L*nz

def line(ax,pts,lw=1.6,color=INK,ls="-",amp=0.4,z=3,alpha=1,dashes=None):
    x,y=wobble(pts,amp); l,=ax.plot(x,y,color=color,lw=lw,ls=ls,zorder=z,alpha=alpha,solid_capstyle="round")
    if dashes: l.set_dashes(dashes)
    return x,y

def river(ax,pts,w=2.6):
    x,y=wobble(pts,0.5)
    ax.plot(x,y,color=(0.42,0.52,0.55),lw=w*2.2,zorder=2,alpha=0.5,solid_capstyle="round")
    ax.plot(x,y,color=INK,lw=w*0.5,zorder=3,alpha=0.8)

def mountain(ax,x,y,s=3,snow=False,z=4):
    h=s*rng.uniform(0.9,1.3); lx=x-s*rng.uniform(0.8,1.1); rx=x+s*rng.uniform(0.8,1.1)
    px=x+rng.uniform(-0.2,0.2)*s; py=y+h
    ax.fill([lx,px,rx],[y,py,y],color=PAPER,zorder=z,alpha=0.95)
    line(ax,[(lx,y),((lx+px)/2,(y+py)/2+0.05*s),(px,py),((px+rx)/2,(py+y)/2),(rx,y)],lw=1.1+0.1*s,amp=0.08,z=z+0.1)
    for k in range(1,6):  # shading on right flank
        f=k/6; sx=px+(rx-px)*f; sy=py+(y-py)*f
        line(ax,[(sx,sy),(sx-0.25*s*(1-f)-0.15*s,y+0.05*s)],lw=0.6,amp=0.03,z=z+0.1)
    if snow:
        ax.fill([px-0.28*s,px,px+0.3*s,px+0.1*s,px-0.08*s],[py-0.35*s,py,py-0.32*s,py-0.25*s,py-0.38*s],color="white",zorder=z+0.05,alpha=0.85)

def hill(ax,x,y,s=3,z=3.5):
    line(ax,[(x-s,y),(x-s*0.4,y+s*0.45),(x+s*0.3,y+s*0.4),(x+s,y)],lw=0.9,amp=0.05,z=z)
    for k in range(3):
        sx=x+s*(0.15+0.22*k); line(ax,[(sx,y+s*0.33-0.1*s*k),(sx-0.2*s,y+0.05*s)],lw=0.5,amp=0.02,z=z)

def tree(ax,x,y,s=1.0,z=4,conifer=False):
    if conifer:
        ax.fill([x-0.6*s,x,x+0.6*s],[y,y+1.8*s,y],color=(0.40,0.45,0.28),alpha=0.55,zorder=z)
        line(ax,[(x-0.6*s,y),(x,y+1.8*s),(x+0.6*s,y)],lw=0.7,amp=0.02,z=z+0.1)
    else:
        th=np.linspace(0,2*np.pi,30); r=0.7*s*(1+0.12*np.sin(5*th+rng.uniform(0,6)))
        ax.fill(x+r*np.cos(th),y+0.9*s+r*np.sin(th),color=(0.45,0.50,0.30),alpha=0.5,zorder=z)
        ax.plot(x+r*np.cos(th),y+0.9*s+r*np.sin(th),color=INK,lw=0.7,zorder=z+0.1)
        ax.plot([x,x],[y,y+0.3*s],color=INK,lw=0.9,zorder=z+0.1)

def forest(ax,cx,cy,rx,ry,n=40,s=1.0,conifer=False):
    pts=[]
    while len(pts)<n:
        u,v=rng.uniform(-1,1,2)
        if u*u+v*v<1: pts.append((cx+u*rx,cy+v*ry))
    for x,y in sorted(pts,key=lambda p:-p[1]): tree(ax,x,y,s*rng.uniform(0.8,1.2),conifer=conifer)

def label(ax,x,y,t,size=14,font=CANON,color=INK,style="normal",rot=0,z=10,ha="center",va="center",weight="normal"):
    ax.text(x,y,t,fontsize=size,family=font,color=color,style=style,rotation=rot,ha=ha,va=va,zorder=z,weight=weight,
            path_effects=[pe.withStroke(linewidth=3.5,foreground=PAPER,alpha=0.9)])

def compass(ax,x,y,r=5):
    for ang,L in [(90,1),(270,1),(0,1),(180,1),(45,0.55),(135,0.55),(225,0.55),(315,0.55)]:
        a=np.radians(ang); tip=(x+r*L*np.cos(a),y+r*L*np.sin(a))
        for side,col in [(1,INK),(-1,PAPER)]:
            b=a+side*np.radians(90); base=(x+0.18*r*np.cos(b),y+0.18*r*np.sin(b))
            ax.fill([x,base[0],tip[0]],[y,base[1],tip[1]],color=col,zorder=8,ec=INK,lw=0.8)
    th=np.linspace(0,2*np.pi,80); ax.plot(x+0.62*r*np.cos(th),y+0.62*r*np.sin(th),color=INK,lw=0.8,zorder=8)
    label(ax,x,y+r*1.25,"N",size=16,font=SC)

def border(ax,W,H):
    for m,lw in [(2.0,2.4),(3.0,0.8)]:
        ax.plot([m,W-m,W-m,m,m],[m,m,H-m,H-m,m],color=INK,lw=lw,zorder=9)

def cartouche(ax,x,y,title,sub,w=60,h=11):
    th=np.linspace(0,np.pi,40)
    ax.fill([x-w/2,x+w/2,x+w/2,x-w/2],[y-h/2,y-h/2,y+h/2,y+h/2],color=PAPER,alpha=0.92,zorder=9,ec=INK,lw=1.5)
    ax.plot([x-w/2+1,x+w/2-1,x+w/2-1,x-w/2+1,x-w/2+1],[y-h/2+1,y-h/2+1,y+h/2-1,y+h/2-1,y-h/2+1],color=INK,lw=0.6,zorder=9.1)
    for sgn in (-1,1):
        cx=x+sgn*(w/2); ax.fill(cx+sgn*2.2*np.sin(th),y+h/2*np.cos(th)*0.8,color=PAPER,ec=INK,lw=1.2,zorder=8.9)
    label(ax,x,y+1.6,title,size=30,font=DECO,z=10)
    label(ax,x,y-3.0,sub,size=14,font=CANON,style="italic",z=10)

def scalebar(ax,x,y,length,text,ticks=4):
    for i in range(ticks):
        ax.fill([x+i*length/ticks,x+(i+1)*length/ticks]*1+[x+(i+1)*length/ticks,x+i*length/ticks],[y,y,y+0.8,y+0.8],
                color=INK if i%2==0 else PAPER,ec=INK,lw=0.8,zorder=8)
    label(ax,x+length/2,y-2.2,text,size=11,style="italic")

def save(fig,path):
    fig.savefig(path,dpi=200); plt.close(fig)
