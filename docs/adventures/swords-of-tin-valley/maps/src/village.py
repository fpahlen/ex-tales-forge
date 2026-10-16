from parch import *
import numpy as np
W,H=150,110
fig,ax=canvas(15,11,seed=41)
ROOF=(0.62,0.30,0.20); GREY=(0.48,0.43,0.38)
def bldg(x,y,w,h,roof=ROOF,rot=0):
    ang=np.radians(rot); c,s_=np.cos(ang),np.sin(ang)
    corners=np.array([(-w/2,-h/2),(w/2,-h/2),(w/2,h/2),(-w/2,h/2)])
    R=np.array([[c,-s_],[s_,c]]); P=corners@R.T+(x,y)
    ax.fill(P[:,0],P[:,1],color=roof,alpha=0.8,zorder=6,ec=INK,lw=1.1)
    a=(P[0]+P[3])/2; b=(P[1]+P[2])/2
    ax.plot([a[0],b[0]],[a[1],b[1]],color=INK,lw=0.8,zorder=6.1)  # ridge
    for f in np.linspace(0.12,0.88,7):
        p=P[0]+(P[1]-P[0])*f; q=P[3]+(P[2]-P[3])*f
        ax.plot([p[0],q[0]],[p[1],q[1]],color=INK,lw=0.35,alpha=0.6,zorder=6.1)
def cap(x,y,t,sub=None,size=12,color=INK,ha="center"):
    label(ax,x,y,t,size=size,font=SC,color=color,ha=ha)
    if sub: label(ax,x,y-2.4,sub,size=9.5,style="italic",color=color,ha=ha)
# river
river(ax,[(98,110),(96,92),(92,74),(93,58),(90,42),(96,24),(104,0)],w=5)
# roads (drawn as double lines)
def road(pts,w=1.4,dash=None,color=INK):
    x,y=wobble(pts,0.15)
    ax.plot(x,y,color=(0.80,0.70,0.52),lw=w*9,zorder=2.5,solid_capstyle="round")
    l,=ax.plot(x,y,color=color,lw=0.6,zorder=2.6,alpha=0.6,ls=(0,(4,3)))
road([(2,48),(20,49),(38,50),(58,52)])
road([(82,50),(100,48),(120,46),(148,44)])
road([(76,58),(84,66),(92,70),(104,76),(114,82)])
# Market square
sq=np.array([(58,44),(82,44),(84,60),(60,61)])
ax.fill(sq[:,0],sq[:,1],color=(0.84,0.75,0.57),zorder=3,ec=INK,lw=1)
for k in range(140):
    px,py=rng.uniform(60,82),rng.uniform(46,59); ax.plot(px,py,".",ms=1,color=INK,alpha=0.35,zorder=3.1)
label(ax,71,50.2,"Market Square",size=17,font=SC)
# well
th=np.linspace(0,2*np.pi,40); ax.fill(71+1.1*np.cos(th),55+1.1*np.sin(th),color=(0.42,0.52,0.55),ec=INK,lw=1,zorder=5)
label(ax,73,55,"well",size=9.5,style="italic",ha="left")
# guild post and stalls
ax.plot([64,64],[54,57.5],color=INK,lw=2,zorder=5); ax.add_patch(plt.Rectangle((62.6,56.4),2.8,1.6,color=PAPER,ec=INK,lw=0.9,zorder=5.1))
label(ax,64,59.2,"guild post",size=9.5,style="italic")
for sx in (76,79):
    ax.add_patch(plt.Rectangle((sx-1,46),2,1.6,color=(0.7,0.6,0.4),ec=INK,lw=0.7,zorder=5))
label(ax,77.5,48.9,"stalls",size=9.5,style="italic")
# buildings
bldg(50,54,10,7); cap(50,61.5,"Valley Inn","Brenna Holt · hearth and bar")
bldg(71,66.5,9,5,roof=GREY); cap(71,72,"Guild office","Osric Vane, steward")
bldg(46,76,11,7,rot=-4); cap(46,84.5,"Harrow house","the headwoman, Maud Harrow")
ax.plot(*wobble([(39,70),(39,82),(53,82),(53,70),(48,70)],0.1),color=INK,lw=0.8,ls=(0,(1,1.2)),zorder=5)  # yard fence
bldg(82,38,6,5,roof=GREY); cap(82,33.5,"Sheriff's house","Elias Crane")
bldg(64,36,5,4,rot=8); cap(64,31.5,"Pell cottage","Agnes Pell")
bldg(28,62,5,4,rot=-10); cap(28,57.6,"Fenn cottage","Ide Fenn")
bldg(60,74,5,4,rot=6); cap(62,79.8,"Carrow cottage","Wil and his mother")
for (x,y,r) in [(36,40,5),(52,40,-6),(30,70,12),(70,80,-8)]: bldg(x,y,4.2,3.4,rot=r)
label(ax,44,36,"widows' cottages",size=9.5,style="italic")
# wagon yard
ax.add_patch(plt.Rectangle((14,38),15,9,fill=False,ec=INK,lw=1.2,ls=(0,(3,1.5)),zorder=5))
for wx in (17,21.5,26):
    ax.add_patch(plt.Rectangle((wx-1.6,40.2),3.2,2.2,color=(0.55,0.38,0.2),ec=INK,lw=0.8,zorder=5.2))
    for d in (-1.2,1.2): ax.add_patch(plt.Circle((wx+d,40.1),0.55,fill=False,ec=INK,lw=0.8,zorder=5.3))
cap(21.5,34.6,"Wagon yard","three wagons for the run")
# training common
ax.add_patch(plt.Rectangle((16,16),26,12,color=(0.72,0.72,0.48),alpha=0.35,ec=INK,lw=0.8,ls=(0,(2,2)),zorder=3))
for k in range(5): ax.plot([20+k*4.5,20+k*4.5],[19,21.5],color=INK,lw=1.2,zorder=4)
cap(29,25,"The common","where the village trains")
# old stockade
stock=[(10,30),(10,90),(66,92),(84,88)]
x,y=wobble(stock,0.2); ax.plot(x,y,color=INK,lw=2.2,zorder=4,ls=(0,(2,0.8)))
x2,y2=wobble([(10,30),(40,13),(62,20)],0.2); ax.plot(x2,y2,color=INK,lw=2.2,zorder=4,ls=(0,(2,0.8)))
label(ax,24,88.5,"old stockade · needs repair",size=10,style="italic",rot=2)
# graves
for gx in np.arange(66,79,2.2):
    for gy in (18,21):
        ax.plot([gx,gx],[gy-0.8,gy+0.8],color=INK,lw=0.9,zorder=5); ax.plot([gx-0.45,gx+0.45],[gy+0.35,gy+0.35],color=INK,lw=0.9,zorder=5)
cap(72,14.5,"Graves","the cave-in dead")
# bridge
for d in (-2.3,2.3): ax.plot([88,95],[49+d,48.5+d],color=INK,lw=1.4,zorder=7)
ax.fill([88,95,95,88],[46.7,46.2,50.8,51.3],color=(0.6,0.45,0.28),zorder=6.9)
ang=np.radians(28); c,s_=np.cos(ang),np.sin(ang)
P=np.array([(-3.6,-2.2),(3.6,-2.2),(3.6,2.2),(-3.6,2.2)])@np.array([[c,-s_],[s_,c]]).T+(92.3,69.2)
ax.fill(P[:,0],P[:,1],color=(0.6,0.45,0.28),zorder=6.9,ec=INK,lw=1.2)
# east bank: smelting sheds, tin sheds, sluice
bldg(108,56,9,5,roof=GREY); bldg(118,58,7,5,roof=GREY,rot=5)
for k in range(3):
    t=np.linspace(0,1,25); ax.plot(108+0.7*np.sin(t*8+k)+k*0.3,59+t*4,color=INK,lw=0.6,alpha=0.6,zorder=6)
cap(108,51.2,"Smelting sheds"); cap(120,63.8,"Tin sheds","one wagon of tin stored")
ax.plot([90.5,96],[62.5,61.5],color=INK,lw=3,zorder=7); cap(99,64.8,"Sluice","cut at night in session 2",size=11,ha="left",color=RED)
# mine entrance, pump house, ore cart rails
mx,my=116,84
ax.fill([mx-3,mx-3,mx+3,mx+3],[my-1.5,my+1.5,my+1.5,my-1.5],color=PAPER,zorder=6,ec=INK,lw=1.2)
ax.fill([mx-2,mx-2,mx+2,mx+2],[my-1.5,my+0.6,my+0.6,my-1.5],color=INK,zorder=6.1)
cap(114,90,"Mine entrance","shaft · ore carts")
bldg(104,88,5,4,roof=GREY); cap(102,93.5,"Pump house","Tomas's pump")
x,y=wobble([(116,82.5),(116,72),(114,64),(112,59)],0.1)
ax.plot(x,y,color=INK,lw=1,zorder=5); ax.plot(x+0.9,y,color=INK,lw=1,zorder=5)
for k in range(0,len(x),4): ax.plot([x[k]-0.3,x[k]+1.2],[y[k],y[k]],color=INK,lw=0.6,zorder=5)
label(ax,121,73,"cart rails",size=9.5,style="italic",ha="left")
# deep drift underground and cave-in site
x,y=wobble([(118,85),(126,90),(134,95),(140,99)],0.2); ax.plot(x,y,color=INK,lw=1.4,ls=(0,(1,1.6)),zorder=5)
cx,cy=140,99
ax.plot([cx-1.8,cx+1.8],[cy-1.8,cy+1.8],color=RED,lw=3,zorder=7); ax.plot([cx-1.8,cx+1.8],[cy+1.8,cy-1.8],color=RED,lw=3,zorder=7)
cap(132,103.5,"Cave-in site","the deep drift, underground",color=RED)
# inn yard (canon)
ax.add_patch(plt.Rectangle((35,53),8,6,fill=False,ec=INK,lw=1,ls=(0,(2,1.5)),zorder=5))
ax.add_patch(plt.Rectangle((36,56.4),3,2,color=(0.55,0.38,0.2),ec=INK,lw=0.6,zorder=5.2))
label(ax,39,51.6,"Inn yard",size=10,font=SC)
# Brask's forge (canon)
bldg(106,40,6,4,roof=GREY)
for k in range(2):
    t=np.linspace(0,1,20); ax.plot(107+0.5*np.sin(t*8+k),42.2+t*3,color=INK,lw=0.5,alpha=0.6,zorder=6)
cap(106,35.6,"Brask's forge","Hilde Brask, smith")
# Maude's cottage (canon)
bldg(20,80,5,4,rot=-6); cap(20,75.4,"Maude's cottage","Old Maude, herb-wife")
# horse whim at the shaft
th=np.linspace(0,2*np.pi,50); ax.plot(124+2.2*np.cos(th),86+2.2*np.sin(th),color=INK,lw=0.9,ls=(0,(2,1)),zorder=6)
ax.plot([124,126.2],[86,87.5],color=INK,lw=1.4,zorder=6); ax.plot(124,86,"o",ms=3,color=INK,zorder=6)
label(ax,127.5,83,"horse whim",size=9.5,style="italic",ha="left")
# road labels
label(ax,10,51.8,"to the Pass and Ferrow",size=10,style="italic",ha="left")
label(ax,147,47.6,"to the Cut (off-route)",size=10,style="italic",ha="right",color=RED)
label(ax,85,67.5,"the tin road",size=10,style="italic",rot=28)
# hills NE
for (hx,hy) in [(128,78),(136,86),(142,74),(124,96)]: hill(ax,hx,hy,s=3.5)
forest(ax,132,30,9,8,n=26,s=1.4,conifer=True)
border(ax,W,H)
cartouche(ax,40,101,"The Village","Tin Valley",w=40,h=11)
compass(ax,140,13,r=5.5)
scalebar(ax,96,8,20,"about 200 paces")
save(fig,"../village.png")
