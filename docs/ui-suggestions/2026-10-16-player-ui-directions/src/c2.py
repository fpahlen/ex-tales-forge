from faces import face
def person(name, role, phrase, shift, glow, f, faded=False):
    op='opacity:.68;' if faded else ''
    return f'''<div class="pp" style="{op}"><div class="por" style="box-shadow:0 0 0 2px {glow},0 0 22px {glow}55">{f}</div>
<div style="flex:1"><div class="nm">{name}</div><div class="role">{role}</div><div class="mood" style="color:{glow}">{phrase}</div><div class="shift">{shift}</div></div></div>'''
elin=face('curious',hair='#6a3a1e',skin='#e2bf9a',bg='#3a3226',female=True)
guild=face('hostile',hair='#1e1a16',skin='#cfa582',bg='#2e2226',beard=True)
brann=face('warm',hair='#9a6a2a',skin='#e0b896',bg='#3a3420')
marit=face('neutral',hair='#4a4a48',skin='#d6b090',bg='#262a32',female=True,old=True)
def mem(text, who, rot, pin='#c44'):
    return f'''<div class="mem" style="transform:rotate({rot}deg)"><span class="pin" style="background:radial-gradient(circle at 35% 35%,{pin},#3a0a0a)"></span>{text}<div class="who">{who}</div></div>'''
html=f'''<html><head><link rel="stylesheet" href="c-common.css"><style>
.bar{{position:absolute;top:0;left:0;right:0;height:64px;display:flex;align-items:center;padding:0 36px;gap:22px;border-bottom:1px solid rgba(233,225,207,.08);background:rgba(10,13,18,.5)}}
.w{{font-family:Inter;font-size:13px;color:#b8c2d0;padding:7px 12px;border-radius:999px;background:rgba(160,180,210,.08);border:1px solid rgba(160,180,210,.15)}}
.w.new{{border-color:rgba(212,176,106,.5);color:#e8d29c}}
.lab{{font-family:Inter;font-size:12px;letter-spacing:2px;text-transform:uppercase;color:#8892a0}}
.left{{position:absolute;left:32px;top:92px;width:310px}}
.pp{{display:flex;gap:16px;align-items:center;padding:14px 0;border-bottom:1px solid rgba(233,225,207,.08)}}
.por{{width:84px;height:84px;border-radius:50%;overflow:hidden;flex:none}}
.por svg{{width:84px;height:84px;filter:sepia(.3) saturate(.85)}}
.nm{{font-size:21px;line-height:1.1}}.role{{font-family:Inter;font-size:12px;color:#8892a0;margin-top:2px}}
.mood{{font-style:italic;font-size:18px;margin-top:5px}}.shift{{font-family:Inter;font-size:12px;color:#aab3c0;margin-top:2px}}
.book{{position:absolute;left:372px;top:88px;width:856px;height:740px;padding:50px 70px 30px 96px;border-radius:3px}}
.book p{{font-size:22.5px;line-height:1.56;margin-bottom:16px;text-align:justify;hyphens:auto}}
.you{{color:#7a2318;font-style:italic}}
.you small{{font-style:normal;font-family:'Cormorant SC';font-size:14px;letter-spacing:1.5px;color:#9b6a50}}
.fate{{position:absolute;left:12px;width:72px;font-size:14.5px;line-height:1.25;font-style:italic;color:#7a5a3a;text-align:right}}
.right{{position:absolute;right:30px;top:92px;width:316px}}
.mem{{background:#efe4c9;color:#2a2016;padding:14px 16px 12px;border-radius:2px;font-size:18.5px;line-height:1.32;box-shadow:0 8px 20px rgba(0,0,0,.5);position:relative;margin-top:22px}}
.mem .who{{font-family:Inter;font-size:11.5px;color:#7a6a58;margin-top:7px;letter-spacing:.3px}}
.pin{{position:absolute;top:-8px;left:50%;width:16px;height:16px;border-radius:50%}}
.input{{position:absolute;left:372px;top:850px;width:856px}}
.ges{{display:flex;gap:9px;flex-wrap:nowrap;white-space:nowrap}}
.g{{font-size:17px;font-style:italic;padding:8px 13px;border-radius:999px;border:1px solid rgba(212,176,106,.35);color:#e9dcc0;background:rgba(212,176,106,.06)}}
.box{{margin-top:14px;display:flex;align-items:center;gap:14px;padding:16px 20px;border-radius:10px;background:rgba(233,225,207,.06);border:1px solid rgba(233,225,207,.18)}}
</style></head><body><div class="rain"></div>
<div class="bar"><div class="sc gold" style="font-size:22px;letter-spacing:4px">Tales Forge</div>
 <div style="font-size:19px;font-style:italic;color:#cfc7b5;margin-left:14px">The Drover's Rest, Ferrow · day one, evening</div>
 <div style="margin-left:auto;display:flex;gap:10px"><span class="w">🌧 Rain turning to sleet</span><span class="w new">❄ First snow on the high peaks</span><span class="w new">⚑ The guild has noticed you</span></div></div>

<div class="left"><div class="lab">In the room</div>
 {person("Elin Harrow","16 · carries the widows' purse","Wary, but listening","She let you sit closer","#d4b06a",elin)}
 {person("The guildsman","Miners Guild · by the fire","Watching you openly","His friend has not come back","#c4574a",guild)}
 {person("Silky Joss","Card sharp","Smiles too much","Keeps glancing at Elin's coat","#8fa6c4",brann)}
 <div class="lab" style="margin-top:22px">Elsewhere</div>
 {person("Marit Harrow","Headwoman of Ferrow","Has not met you","Will know you by Elin's telling","#8892a0",marit,True)}
 <div class="lab" style="margin-top:26px">How Elin sees you</div>
 <div style="margin-top:12px;font-size:18px;font-style:italic;line-height:1.9;color:#cfc7b5">
  <div style="color:#8892a0">a stranger at the door</div>
  <div style="color:#aab3c0">↓ &nbsp;another sellsword</div>
  <div style="color:#d4b06a">↓ &nbsp;someone who listened</div></div>
</div>

<div class="vellum book">
 <div class="sc rub" style="font-size:16px;letter-spacing:3px;text-align:center">Chapter the Second</div>
 <div class="sc" style="font-size:34px;text-align:center;margin:2px 0 22px">The Widows' Purse</div>
 <p><span class="drop">R</span>ain comes off the mountain in grey sheets, and the Drover's Rest smells of wet wool and tallow. Three guildsmen hold the table nearest the fire as though they had paid for the hearth itself. By the door sits a girl of sixteen, one hand pressed flat over something under her coat. Two sellswords are still laughing at whatever she asked them.</p>
 <p class="you">"Half this room has watched you guard that coat." <small>you said</small></p>
 <p>Elin Harrow looks at you the way miners look at a cracked beam. <i>"It's the widows' purse, not mine. Eleven families, and the guild says the mine owes them nothing."</i></p>
 <p>When you look again, the bench by the fire holds only two men. You did not see the third one go. The door to the yard swings on its leather hinge.</p>
 <p class="you">"Stay close. Is there another way out?" <small>you said</small></p>
 <p><i>"Through the kitchen. The pot-boy showed me last night."</i> Her hand stays on her coat. By the cards, a man in a yellow doublet smiles at nothing.</p>
 <div class="fate" style="top:452px"><span style="font-size:22px;color:#9b2d20;font-style:normal">✶</span><br>Fate turned. Something slipped past you.</div>
 <div style="position:absolute;bottom:26px;left:96px;right:70px;display:flex;justify-content:space-between;font-family:Inter;font-size:12px;color:#8a7458"><span>✶ marks a hidden roll · a miss can still teach you</span><span>folio 14</span></div>
</div>

<div class="input">
 <div class="ges"><span class="g">✋ Cover the purse with your hand</span><span class="g">👁 Watch the yard door</span><span class="g">🍺 Push your ale toward her</span><span class="g">🗝 Nod toward the kitchen</span></div>
 <div class="box"><span style="font-size:21px;font-style:italic;color:#8f887a;flex:1">Speak as Corin, or describe what you do…</span><span class="ui" style="font-size:12px;color:#8892a0">( ) for a word to the GM</span><span class="ui wbtn" style="font-size:14px;font-weight:600;color:#1a1408;background:#d4b06a;padding:9px 16px;border-radius:8px">Write ↵</span></div>
</div>

<div class="right"><div class="lab">Memories</div>
 {mem("You told Elin you sell your sword, not your name.","Elin remembers this",-1.5)}
 {mem("Eleven families in Tin Valley. The guild says the mine owes them nothing.","You learned this tonight",1.2,"#d4b06a")}
 {mem("Someone left by the yard door while you weren't looking.","You remember this",-1,"#7a8aa8")}
 <div style="margin-top:28px;padding:16px;border-radius:8px;border:1px solid rgba(233,225,207,.15)">
  <div class="lab">The pass</div>
  <svg width="284" height="60" viewBox="0 0 284 60" style="margin-top:8px"><path d="M0 60 L70 18 L110 38 L160 6 L210 34 L250 20 L284 40 L284 60Z" fill="#2a3340"/><path d="M48 31 L70 18 L110 38 L160 6 L210 34 L250 20 L270 31" fill="none" stroke="#e9eef5" stroke-width="3" opacity=".85"/><line x1="0" y1="30" x2="284" y2="30" stroke="#d4b06a" stroke-dasharray="4 4" opacity=".6"/></svg>
  <div style="font-size:18px;font-style:italic;color:#cfc7b5;margin-top:6px">Open for now. It closes with the first heavy snow.</div></div>
 <div style="margin-top:18px;padding:14px 16px;border-radius:8px;border:1px solid rgba(233,225,207,.15);display:flex;align-items:center;gap:12px">
  <div style="flex:1"><div class="lab">Dice</div><div style="font-size:17px;font-style:italic;color:#cfc7b5;margin-top:4px">Hidden. The story tells you how it went.</div></div>
  <span style="width:38px;height:20px;border-radius:10px;background:#2a313c;border:1px solid #4a5464;position:relative;flex:none"><span style="position:absolute;left:3px;top:3px;width:12px;height:12px;border-radius:50%;background:#8892a0"></span></span></div>
</div>
</body></html>'''
open('c2.html','w').write(html)
