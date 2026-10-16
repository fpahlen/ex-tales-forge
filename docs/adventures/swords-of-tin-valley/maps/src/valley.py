from parch import *
import numpy as np
W,H=150,110
fig,ax=canvas(15,11,seed=23)
keep=[(5,62,88,108),(60,125,40,90),(20,60,20,44),(0,40,50,75),(115,150,38,58),(120,150,3,27),(3,50,3,18)]
def free(x,y): return not any(a<=x<=b and c<=y<=d for a,b,c,d in keep)
for _ in range(140):
    x=rng.uniform(5,145); y=rng.uniform(84,102)-0.0*x
    if free(x,y): mountain(ax,x,y,s=rng.uniform(3,4.5),snow=rng.random()<0.35)
for _ in range(40):
    x=rng.uniform(5,145); y=rng.uniform(70,86)
    if free(x,y): hill(ax,x,y,s=rng.uniform(3,4.5))
for _ in range(30):
    x=rng.uniform(55,145); y=rng.uniform(8,30)
    if free(x,y): hill(ax,x,y,s=rng.uniform(3,4))
# woods
forest(ax,118,64,9,6,n=34,s=1.3,conifer=True)
forest(ax,36,32,14,7,n=40,s=1.3,conifer=True)
forest(ax,95,22,10,5,n=22,s=1.2)
# river from the north through the valley
river(ax,[(92,104),(90,88),(86,72),(84,60),(80,50),(84,38),(96,24),(108,3)],w=3.2)
# roads
pass_road=[(4,64),(16,60),(30,52),(44,48),(56,48),(66,49)]
line(ax,pass_road,lw=2.8,color=RED,dashes=[5,2.5],amp=0.2,z=7)
label(ax,22,65.5,"the pass road",size=13,style="italic",rot=-18)
label(ax,29,49.6,"to the Pass and Ferrow · 3 days",size=10.5,style="italic",rot=-18)
tin_road=[(70,52),(76,60),(88,66),(97,71)]
line(ax,tin_road,lw=2.0,dashes=[3,2],amp=0.2,z=6)
label(ax,79,63.8,"the tin road",size=11,style="italic",rot=28)
valley_road=[(76,50),(84,48),(98,47),(112,48),(128,50),(146,52)]
line(ax,valley_road,lw=1.7,dashes=[3,2],amp=0.2,z=6)
label(ax,131,55,"the valley road",size=12,style="italic",rot=3)
label(ax,131,45.5,"east to the Cut above the nest",size=10.5,style="italic",color=RED)
label(ax,131,42.5,"(off-route)",size=10,style="italic",color=RED)
# bridge
ax.plot([80.5,80.5],[47,49.8],color=INK,lw=1); ax.plot([83,83],[46.5,49.4],color=INK,lw=1)
# village cluster
def house(x,y,w=2.2,h=1.6,roof=RED):
    ax.add_patch(plt.Rectangle((x-w/2,y-h/2),w,h,color=PAPER,ec=INK,lw=0.9,zorder=6))
    ax.fill([x-w/2-0.3,x,x+w/2+0.3],[y+h/2,y+h/2+1.2,y+h/2],color=roof,alpha=0.75,ec=INK,lw=0.6,zorder=6.1)
for (x,y) in [(68,50),(71,53),(74,49),(72,46),(66,46.5),(76,53),(77,46)]: house(x,y)
label(ax,72,41.5,"The village",size=18,font=SC)
label(ax,72,38.6,"eleven households · about 34 souls",size=10,style="italic")
label(ax,62.5,53.5,"Valley Inn",size=11,font=SC,ha="right")
label(ax,62.5,51,"at the foot of the tin road",size=9,style="italic",ha="right")
# wagon yard
ax.add_patch(plt.Rectangle((57,44),5,3,fill=False,ec=INK,lw=1,zorder=6,ls=(0,(2,1))))
for dx in (58.2,60.8):
    ax.add_patch(plt.Rectangle((dx-0.8,45),1.6,1,color=(0.55,0.38,0.2),ec=INK,lw=0.5,zorder=6.2))
label(ax,59.5,42.2,"Wagon yard",size=10,font=SC)
# graves
for gx,gy in [(67,32),(69,32.4),(71,31.8),(73,32.3),(75,31.9),(67.6,29.9),(69.6,30.3),(71.6,29.8),(73.6,30.2),(75.6,29.9)]:
    ax.plot([gx,gx],[gy-0.6,gy+0.6],color=INK,lw=0.8,zorder=6); ax.plot([gx-0.35,gx+0.35],[gy+0.25,gy+0.25],color=INK,lw=0.8,zorder=6)
label(ax,71,27.6,"Graves of the ten cave-in dead",size=10,style="italic")
# smelting sheds and sluice
for (x,y) in [(90,58),(93,57)]: house(x,y,w=2.6,h=1.5,roof=(0.4,0.35,0.3))
for k in range(3):
    t=np.linspace(0,1,20); ax.plot(93.5+0.5*np.sin(t*8+k)+k*0.2,58.8+t*3,color=INK,lw=0.5,alpha=0.6,zorder=6)
label(ax,97,61.5,"Smelting sheds",size=11,font=SC,ha="left")
label(ax,97,59.2,"tin sheds (one wagon stored)",size=9,style="italic",ha="left")
ax.plot([79.8,83.6],[43.4,42.4],color=INK,lw=2.4,zorder=7)
label(ax,86,43.2,"Sluice",size=11,font=SC,ha="left")
label(ax,86,41,"cut at night (session 2)",size=9,style="italic",ha="left",color=RED)
# mine
mx,my=98,72
ax.fill([mx-1.8,mx,mx+1.8],[my-1.2,my+1.8,my-1.2],color=INK,zorder=6)
ax.plot([mx-2,mx+2],[my-1.4,my-1.4],color=INK,lw=1.6,zorder=6)
label(ax,mx+3,my+1,"Mine workings",size=13,font=SC,ha="left")
label(ax,mx+3,my-1.6,"shaft · horse whim · ore carts",size=9.5,style="italic",ha="left")
house(92,72.5,w=2.2,h=1.4,roof=(0.4,0.35,0.3))
label(ax,90.5,75.6,"Pump house",size=10,font=SC,ha="right")
# deep drift (underground, dotted) and cave-in
line(ax,[(mx,my-1),(104,77),(111,81),(116,84)],lw=1.2,color=INK,dashes=[1,1.5],amp=0.2,z=6)
cx,cy=116,84
ax.plot([cx-1.3,cx+1.3],[cy-1.3,cy+1.3],color=RED,lw=2.4,zorder=7); ax.plot([cx-1.3,cx+1.3],[cy+1.3,cy-1.3],color=RED,lw=2.4,zorder=7)
label(ax,119,86.5,"The deep drift",size=12,font=SC,ha="left",color=RED)
label(ax,119,84,"cave-in site (underground)",size=9.5,style="italic",ha="left",color=RED)
label(ax,118,75.5,"Timber wood",size=12,font=SC)
label(ax,118,73.1,"pit props",size=9.5,style="italic")
# Dace's camp
tx,ty=40,38
for dx in (-1.5,0,1.6):
    ax.fill([tx+dx-1,tx+dx,tx+dx+1],[ty,ty+1.8,ty],color=PAPER,ec=INK,lw=0.8,zorder=6.5)
ax.plot([tx+0.2,tx+0.2],[ty-1.2,ty-0.4],color=RED,lw=1.5,zorder=6.5)
label(ax,40,22.5,"Dace Morrow's camp",size=12,font=SC)
label(ax,40,20,"the hired blades",size=9.5,style="italic")
# west road (canon) and old adit in the pines
label(ax,39,53.2,"the west road",size=10.5,style="italic",rot=-14)
forest(ax,40,66,6,3.5,n=14,s=1.1,conifer=True)
ax.fill([44.2,45.6,47,47,44.2],[61,62.6,61,59.6,59.6],color=INK,zorder=6.5)
label(ax,46,57.6,"Old adit",size=11,font=SC)
label(ax,40,72,"pines",size=9,style="italic")
# charcoal kilns
for kx,ky in [(105,26.5),(109,25),(107.5,29)]:
    t=np.linspace(0,np.pi,30); ax.fill(kx+1.6*np.cos(t),ky+1.1*np.sin(t),color=(0.35,0.3,0.25),ec=INK,lw=0.8,zorder=6.5)
    tt=np.linspace(0,1,20); ax.plot(kx+0.4*np.sin(tt*9),ky+1.1+tt*2.5,color=INK,lw=0.5,alpha=0.6,zorder=6.5)
label(ax,112,27,"Charcoal kilns",size=11,font=SC,ha="left")
label(ax,112,24.7,"the Burrow household",size=9,style="italic",ha="left")
# fields
for fx0,fy0 in [(52,56),(56,59),(60,62)]:
    for k in range(4):
        line(ax,[(fx0,fy0+k*0.7),(fx0+4,fy0+k*0.7+0.5)],lw=0.5,amp=0.02,z=4)
border(ax,W,H)
cartouche(ax,33,98,"The Valley","village, mine and roads",w=46,h=12)
compass(ax,138,15,r=6)
scalebar(ax,10,10,24,"about one mile")
save(fig,"../valley.png")
