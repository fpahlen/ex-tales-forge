from faces import face
html=f'''<html><head><link rel="stylesheet" href="c-common.css"><style>
.mtn{{position:absolute;left:0;right:0;bottom:0}}
.top{{position:absolute;top:26px;left:40px;right:40px;display:flex;justify-content:space-between;align-items:center}}
.seals{{display:flex;gap:30px;align-items:center}}
.seal{{display:flex;flex-direction:column;align-items:center;gap:6px;font-size:15px;color:#9aa4b2}}
.seal i{{width:34px;height:34px;border-radius:50%;background:#2a313c;border:1px solid #4a5464;display:block}}
.seal.done i{{background:radial-gradient(circle at 35% 35%,#c4473a,#6a1810);border:0}}
.seal.on{{color:#f0e6cf}}.seal.on i{{background:radial-gradient(circle at 35% 35%,#e0c27a,#8a6420);border:0;box-shadow:0 0 18px rgba(224,194,122,.5)}}
.page{{position:absolute;left:470px;top:110px;width:660px;height:770px;padding:50px 60px;border-radius:3px}}
.page p{{font-size:23px;line-height:1.5;margin-bottom:18px}}
.choice{{display:flex;gap:16px;align-items:flex-start;padding:15px 18px;border:1px solid rgba(90,60,30,.35);border-radius:6px;margin-bottom:12px;background:rgba(255,250,235,.35);font-size:21px;line-height:1.35}}
.choice b{{font-family:'Cormorant SC';font-size:15px;letter-spacing:1.5px;color:#9b2d20;display:block;margin-top:4px;font-weight:600}}
.choice.hov{{border-color:#9b2d20;background:rgba(155,45,32,.08);box-shadow:0 0 0 1px #9b2d20}}
.left{{position:absolute;left:60px;top:150px;width:360px}}
.right{{position:absolute;right:60px;top:150px;width:360px}}
.trait{{font-size:22px;font-style:italic;color:#e9e1cf;padding:12px 0;border-bottom:1px solid rgba(233,225,207,.12);line-height:1.3}}
.trait small{{display:block;font-style:normal;font-family:Inter;font-size:12.5px;color:#8892a0;margin-top:3px}}
.lab{{font-family:Inter;font-size:12px;letter-spacing:2px;text-transform:uppercase;color:#8892a0}}
</style></head><body>
<svg class="mtn" width="1600" height="420" viewBox="0 0 1600 420"><path d="M0 420 L0 250 L160 140 L260 200 L420 60 L560 210 L700 130 L820 230 L980 90 L1120 220 L1260 110 L1420 230 L1600 150 L1600 420Z" fill="#1b222c"/><path d="M420 60 L470 110 L440 104 L410 120 L380 96Z M980 90 L1030 140 L1000 132 L970 146 L945 122Z M1260 110 L1300 150 L1270 144 L1245 156Z" fill="#c8d2de" opacity=".5"/><path d="M0 420 L0 330 L200 270 L380 330 L600 280 L800 340 L1040 290 L1240 340 L1460 300 L1600 330 L1600 420Z" fill="#11161d"/></svg>
<div class="rain"></div>
<div class="top"><div class="sc" style="font-size:26px;color:#d4b06a;letter-spacing:4px">Tales Forge</div>
 <div class="seals"><div class="seal done"><i></i>The Road</div><div class="seal on"><i></i>The Pass</div><div class="seal"><i></i>The Debt</div><div class="seal"><i></i>The Name</div></div>
 <div class="ui" style="font-size:13px;color:#8892a0">Prologue · 2 of 4</div></div>

<div class="left">
 <div class="lab">Who you are becoming</div>
 <div style="margin:18px 0 10px;display:flex;gap:18px;align-items:center">
  <div style="width:120px;height:150px;border-radius:60px 60px 6px 6px;overflow:hidden;border:1px solid #4a5464;opacity:.9;filter:sepia(.4)"><svg width="120" height="150" viewBox="0 0 120 150"><rect width="120" height="150" fill="#232a34"/><g stroke="#cfc3a6" stroke-width="1.4" fill="none" opacity=".75"><path d="M60 30 Q36 32 36 64 Q36 96 60 104 Q84 96 84 64 Q84 32 60 30"/><path d="M38 60 Q40 34 62 30" stroke-dasharray="3 4"/><path d="M48 66 L54 66 M66 66 L72 66" opacity=".6"/><path d="M60 70 L57 82 L62 83" opacity=".6"/><path d="M20 150 Q24 116 60 112 Q96 116 100 150" /><path d="M46 104 L44 116 M74 104 L76 116" stroke-dasharray="2 3"/></g></svg></div>
  <div style="font-size:20px;font-style:italic;color:#b8b0a0;line-height:1.35">A face the valley has not yet learned.<div class="ui" style="font-size:12.5px;font-style:normal;color:#8892a0;margin-top:8px">Your name comes last, as it does in songs.</div></div></div>
 <div class="trait">Born to the drovers' road<small>from The Road</small></div>
 <div class="trait">Steady hands with frightened beasts<small>from The Road</small></div>
 <div class="trait" style="color:#8892a0">…<small>this scene will add more</small></div>
 <div class="lab" style="margin-top:34px">Your voice, so far</div>
 <div style="margin-top:12px;font-size:21px;line-height:1.4;font-style:italic;color:#d9cfb8;border-left:2px solid #9b2d20;padding-left:14px">"Hush now, girl. Hush. The road's long, but it ends."</div>
 <div class="ui" style="font-size:12.5px;color:#8892a0;margin-top:8px;padding-left:16px">You said this to your father's mule, in The Road</div>
</div>

<div class="vellum page">
 <div class="sc rub" style="font-size:17px;letter-spacing:3px;text-align:center">Prologue · II</div>
 <div class="sc" style="font-size:36px;text-align:center;margin:4px 0 26px;color:#2a2016">The Pass, Nine Winters Ago</div>
 <p><span class="drop">Y</span>our father's mule went down on the ice above the Gullet, and did not get up. The packs held everything you owned. Below, the lamps of Ferrow. Behind, the wind, and the sound of it was like something counting.</p>
 <p style="font-style:italic;color:#5a3a20">You were fourteen. What did you do?</p>
 <div class="choice"><span style="font-size:26px">✋</span><div>Knelt in the snow and sat with her until she was still.<b>Patience · mercy · the cold gets in</b></div></div>
 <div class="choice hov"><span style="font-size:26px">⚒</span><div>Cut the packs loose and carried what you could down the mountain.<b>Strength · stubbornness · loss</b></div></div>
 <div class="choice"><span style="font-size:26px">⚖</span><div>Skinned her, and sold the hide in Ferrow by noon.<b>Cunning · trade · a hard name</b></div></div>
 <div style="border-bottom:1px solid rgba(90,60,30,.5);padding:10px 4px;font-size:21px;font-style:italic;color:#8a7458;margin-top:18px">Or tell it in your own words…</div>
</div>

<div class="right">
 <div class="lab">What this shapes</div>
 <div style="font-size:21px;line-height:1.45;color:#cfc7b5;margin-top:16px;font-style:italic">There are no forms to fill. Every answer quietly sets your six traits and the skills you begin with.</div>
 <div style="margin-top:22px;padding:18px;border:1px solid rgba(212,176,106,.35);border-radius:8px;background:rgba(212,176,106,.06)">
  <div class="sc gold" style="font-size:17px">Carried down the mountain</div>
  <div style="font-size:19px;line-height:1.45;margin-top:8px;color:#e9e1cf">Your back grows broad and your temper grows short. You will know the pass better than most.</div>
  <div class="ui" style="font-size:12.5px;color:#8892a0;margin-top:10px">Leans toward Strength, Constitution, Lore of the pass</div>
 </div>
 <div style="margin-top:26px" class="lab">Remembered</div>
 <div style="margin-top:12px;background:#efe4c9;color:#2a2016;padding:14px 16px;border-radius:3px;transform:rotate(-1.5deg);font-size:18.5px;line-height:1.35;box-shadow:0 8px 20px rgba(0,0,0,.5);position:relative"><span style="position:absolute;top:-8px;left:50%;width:16px;height:16px;border-radius:50%;background:radial-gradient(circle at 35% 35%,#e66,#7a1010)"></span>You buried your father on the drovers' road, under a cairn of river stones.</div>
 <div class="ui" style="margin-top:40px;display:flex;align-items:center;gap:10px;font-size:13px;color:#8892a0"><span style="width:34px;height:18px;border-radius:9px;background:#2a313c;border:1px solid #4a5464;display:inline-block;position:relative"><span style="position:absolute;left:2px;top:2px;width:12px;height:12px;border-radius:50%;background:#8892a0"></span></span>Show the numbers behind the story</div>
</div>
<div class="ui cap" style="position:absolute;bottom:34px;left:0;right:0;text-align:center;font-size:13px;color:#8892a0;letter-spacing:.5px">Choose a gesture, or write your own · the Game Master will follow where you lead</div>
</body></html>'''
open('c1.html','w').write(html)
