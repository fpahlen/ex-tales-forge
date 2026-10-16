from parch import *
W,H=150,110
fig,ax=canvas(15,11,seed=11)
import numpy as np
# keep-out boxes for labels
keep=[(14,68,88,108),(54,90,40,61),(40,58,50,61),(88,122,40,66),(120,150,48,72),(5,55,3,22),(125,150,3,27),(22,48,38,52)]
def free(x,y): return not any(a<=x<=b and c<=y<=d for a,b,c,d in keep)
# Main range N-S with pass gap
for _ in range(260):
    y=rng.uniform(8,100); x=70+6*np.sin(y/14)+rng.normal(0,6)
    if free(x,y): mountain(ax,x,y,s=rng.uniform(2.4,3.6),snow=rng.random()<0.45)
# Northern ridge above the valley
for _ in range(70):
    x=rng.uniform(84,145); y=rng.uniform(78,100)
    if free(x,y): mountain(ax,x,y,s=rng.uniform(2.2,3.2),snow=rng.random()<0.3)
# Southern hills of the valley
for _ in range(25):
    x=rng.uniform(88,125); y=rng.uniform(28,38)
    if free(x,y): hill(ax,x,y,s=rng.uniform(2,3))
# Guild lands hills
for _ in range(25):
    x=rng.uniform(10,55); y=rng.uniform(25,80)
    if free(x,y) and ((x-32)/22)**2+((y-52)/27)**2<1: hill(ax,x,y,s=rng.uniform(2,3))
# forests
forest(ax,110,18,12,6,n=30,conifer=True); forest(ax,140,40,6,6,n=14,conifer=True)
forest(ax,142,80,5,3,n=8,conifer=True)
# rivers
river(ax,[(100,88),(103,74),(98,62),(104,46),(112,36),(122,22),(132,4)])
river(ax,[(60,88),(50,72),(42,57),(40.5,48),(44,38),(48,22),(52,4)])
# guild lands boundary
th=np.linspace(0,2*np.pi,200)
line(ax,list(zip(32+24*np.cos(th),52+29*np.sin(th))),lw=1.4,color=RED,amp=0.3,dashes=[6,3,1,3],z=3)
label(ax,32,86,"The Guild Lands",size=20,font=SC,color=RED)
label(ax,32,82.5,"chartered for iron, copper and lead",size=11,style="italic",color=RED)
# workings
for (x,y,t) in [(18,66,"Iron workings"),(36,69,"Copper workings")]:
    ax.plot([x-1,x+1],[y-1,y+1],color=INK,lw=1.4,zorder=6); ax.plot([x-1,x+1],[y+1,y-1],color=INK,lw=1.4,zorder=6)
    label(ax,x,y-3,t,size=11,style="italic")
label(ax,18,60.5,"(seams running thin)",size=9.5,style="italic")
# Ferrow
fx,fy=34,45
for dx,dy in [(-2,1),(0,2),(2,0.5),(-1,-1.5),(1.5,-1.8),(3,2)]:
    ax.add_patch(plt.Rectangle((fx+dx-0.8,fy+dy-0.6),1.6,1.2,color=PAPER,ec=INK,lw=0.9,zorder=6))
    ax.fill([fx+dx-1,fx+dx,fx+dx+1],[fy+dy+0.6,fy+dy+1.5,fy+dy+0.6],color=RED,alpha=0.7,zorder=6.1,ec=INK,lw=0.6)
th2=np.linspace(0,2*np.pi,60); line(ax,list(zip(fx+0.5+5*np.cos(th2),fy+0.3+4*np.sin(th2))),lw=1.2,amp=0.1,z=6)
label(ax,fx-6,fy-7,"Ferrow",size=24,font=SC)
label(ax,fx-6,fy-10.3,"market town · guild hall",size=10,style="italic")
label(ax,fx-6,fy-12.6,"Coldwater counting house",size=10,style="italic"); label(ax,fx-6,fy-14.9,"the Margrave's registry",size=10,style="italic"); label(ax,fx-6,fy-17.2,"the Drover's Rest (inn)",size=10,style="italic")
# Pass road
road=[(fx+5,fy+1),(48,47),(57,50),(63,52.5),(70,54),(77,53),(84,51.5),(92,50),(100,50)]
line(ax,road,lw=2.6,color=RED,amp=0.15,dashes=[5,2.5],z=7)
label(ax,63,48.2,"The Narrows",size=13,font=SC)
label(ax,73,58.5,"The Pass",size=18,font=SC)
label(ax,49,55,"the pass road",size=11,style="italic",rot=14)
label(ax,49.5,52.2,"3 days by wagon",size=10,style="italic",rot=14)
label(ax,79,45,"closes with the first heavy snow",size=10.5,style="italic",color=RED)
# Tin Valley
label(ax,108,72,"Tin Valley",size=26,font=SC)
vx,vy=101,50
for dx,dy in [(-1.5,0.5),(0.5,1.5),(1.8,-0.5),(-0.3,-1.4)]:
    ax.add_patch(plt.Rectangle((vx+dx-0.7,vy+dy-0.5),1.4,1.0,color=PAPER,ec=INK,lw=0.9,zorder=6))
    ax.fill([vx+dx-0.9,vx+dx,vx+dx+0.9],[vy+dy+0.5,vy+dy+1.3,vy+dy+0.5],color=RED,alpha=0.7,zorder=6.1,ec=INK,lw=0.6)
label(ax,vx,vy-4,"The village",size=14,font=SC)
label(ax,vx,vy-6.6,"Valley Inn · Market Square",size=10,style="italic")
# mine
mx,my=110,61
ax.fill([mx-1.4,mx,mx+1.4],[my-1,my+1.4,my-1],color=INK,zorder=6)
ax.plot([mx-1.6,mx+1.6],[my-1.2,my-1.2],color=INK,lw=1.5,zorder=6)
label(ax,mx+1,my+3.2,"Tin mine",size=13,font=SC)
line(ax,[(vx+2,vy+1),(105,55),(mx,my-1.2)],lw=1.4,dashes=[3,2],amp=0.1,z=5)
label(ax,113,55,"the tin road",size=9.5,style="italic",rot=50)
# valley road east to the cut
line(ax,[(vx+3,vy),(110,51),(118,52),(126,54)],lw=1.5,dashes=[3,2],amp=0.15,z=5)
label(ax,116,49.3,"the valley road",size=10,style="italic",rot=6)
label(ax,131,55.5,"Cut above the nest",size=12,font=SC)
line(ax,[(126,54),(130,58),(133,61),(137,64)],lw=1.1,dashes=[1,2],amp=0.2,z=5)
for k in range(4):  # smoke
    th3=np.linspace(0,1,30); ax.plot(139+0.6*np.sin(th3*9+k)+k*0.3,66+th3*3+k*0.2,color=INK,lw=0.5,alpha=0.6,zorder=6)
for dx in (-1.2,0,1.3):
    ax.fill([138+dx-0.8,138+dx,138+dx+0.8],[64,65.6,64],color=(0.5,0.35,0.2),ec=INK,lw=0.6,zorder=6)
label(ax,138.5,70.5,"Orc nest",size=14,font=SC,color=RED)
label(ax,137.5,61,"off-route · held in reserve",size=9.5,style="italic",color=RED)
# title, compass, legend
border(ax,W,H)
cartouche(ax,41,99,"Tin Valley","and the road to Ferrow",w=50,h=12)
compass(ax,139,15,r=6)
lx,ly=9,17
label(ax,lx+20,ly+3.5,"Legend",size=14,font=SC)
line(ax,[(lx,ly),(lx+7,ly)],lw=2.6,color=RED,dashes=[5,2.5],amp=0.01,z=8); label(ax,lx+9,ly,"wagon route (the run)",size=11,ha="left")
line(ax,[(lx,ly-3.5),(lx+7,ly-3.5)],lw=1.5,dashes=[3,2],amp=0.01,z=8); label(ax,lx+9,ly-3.5,"track",size=11,ha="left")
line(ax,[(lx,ly-7),(lx+7,ly-7)],lw=1.4,color=RED,dashes=[6,3,1,3],amp=0.01,z=8); label(ax,lx+9,ly-7,"guild lands",size=11,ha="left")
line(ax,[(lx+26,ly),(lx+33,ly)],lw=1.1,dashes=[1,2],amp=0.01,z=8); label(ax,lx+35,ly,"goat path",size=11,ha="left")
save(fig,"../region.png")
