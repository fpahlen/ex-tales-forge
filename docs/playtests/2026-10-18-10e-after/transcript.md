# Transcript: GameCharacter 10e AFTER run, 2026-10-18

- Site: Tales Forge playtest, https://tales-forge-playtest.fly.dev (never prod).
- Session: https://tales-forge-playtest.fly.dev/play/3705591b-f2f8-4f03-8114-fca1368b6ff1 (Tin Valley, quick start Elara Voss, not renamed). Quick start clicked once; one session, no duplicate.
- Build: admin badge "PLAYTEST 4a2b01e" (main after #445 Refactor 10e; #443 10f PR 1 is also in) at the start, after T9, after T21 and after T38 (10:51:58 CEST). It never changed. #446 and #448 merged on GitHub at 10:48 CEST, during T22, but they were not deployed to playtest before the run ended.
- Window: 1280×800 desktop.
- Play time: quick start 10:41:38 CEST, T1 sent 10:41:49, T38 done 10:51:10 CEST. Script: `../2026-10-18-10e-before/script.md`, replayed word for word.
- 38 script inputs plus 4 sub-turns (7b, 8b and 32a are clarify answers; 10b is the travel retry) = 42 entries. Admin shows 39 turns (admin #1 is the opening and a clarify answer is stored with its turn).
- State line format: turn time | time of day (play header) | location | PRESENT | coins | wounds | inventory.
- Turn time: from clicking Act until the input re-enabled, polled every 400 ms. Block B–C (T10–T21) logged only a range: every turn returned within about 2–10 s.
- Session-level clock after the last turn: world_tick 144, world_clock "Day 2 · evening" (admin world state).
- No 💭 thought appeared on any turn. No GM prompt or system text leaked.

## T0 start
~0.5 s load | Day 1 · late afternoon | Valley Inn | PRESENT Brenna Holt (innkeep · troubled) | 2g 10s 0c | wounds 0/3 | travel cloak, hunting knife | Insight 15%, Melee combat 10%, Persuasion 25%, Stealth 20%
GM ("You arrive at Valley Inn"): You push open the heavy door and step into the Valley Inn, a wave of warm air thick with woodsmoke, spilled ale, and the sharp tang of onions frying on the hearth. Low rafters sag under years of soot, and the long bar counter gleams from countless wiped spills. Miners in patched coats hunch over their mugs, their low murmurs mixing with the scrape of wooden spoons and the occasional burst of laughter. Brenna Holt stands behind the bar, sleeves dusted with flour, her broad smile flashing as she glances your way. The room feels lived-in and watchful, the hills outside pressing close against the windows.

Brenna sets down her cloth and leans forward, voice carrying easily across the space. "New face at my door! Come in, love, before the wind steals the heat. What brings you down the tin road today?" Her eyes are kind but appraising, the cheerful host who sees every newcomer as a story waiting to unfold. The miners quiet a fraction, curious glances flicking toward you.

The door behind you creaks in the draft, and the valley road lies just beyond it, waiting.

## T1 | I look around the common room. Who is here?
time: 5.8 s (sent 10:41:49) | late afternoon | Valley Inn | Brenna Holt | 2g 10s 0c | 0/3 | cloak, knife
Notes: repeats her opening greeting word for word. Free ale in prose, not on the sheet.
GM: You take in the low-beamed room, the hearth crackling beneath a blackened pot of onions, the handful of miners hunched at scarred tables with their heads close together. Brenna Holt straightens from wiping the bar, her smile widening as she catches your eye. "New face at my door! Come in, love, before the wind steals the heat. What brings you down the tin road today?"

She pours a mug of ale without being asked and slides it across to you, the foam catching the firelight. "First one on the house for anyone who looks like they've walked the cut," she adds with a wink, though her gaze flicks briefly to the knife at your belt. The miners have gone back to their low conversation, but one or two still glance your way. Outside, the valley road waits, and the late afternoon light is already softening against the hills.

Brenna leans on the counter, clearly ready to talk if you are. "If you're after honest work, Osric Vane up in the square pays good silver to anyone with steel who'll clear the orc nest off the cut. Or I could use an extra pair of hands tonight if the room and board sound fair."

## T2 | I walk up to the innkeeper and say: "Good evening. My sister Wren makes lamps in Kestrel Ford. She sent me up the valley to find work."
time: 6.3 s (sent 10:42:01) | late afternoon | Valley Inn | Brenna Holt | 2g 10s 0c | 0/3 | cloak, knife
Notes: Wren and Kestrel Ford echoed; invents surname "Voss", tin lanterns, and Caldern as kin. Second free ale in prose only.
GM: You step up to the bar and introduce yourself as Wren's sister from Kestrel Ford, looking for work in the valley. Brenna's eyes light up with recognition at the name. "Wren Voss? The one who casts those clever tin lanterns? Well then, Elara, you're practically family already. Sit yourself down." She slides a foaming mug of ale across without asking for coin. "Drink that while it's cold. Work's thick as fog up here if you've got steady hands or a sharp eye. Osric Vane over in the Market Square pays silver for anyone willing to clear the orc nest that's been raiding the cut. Or I could use an extra pair of hands tonight; the miners are thirsty and the pot's low on stew. Either way, you'll eat free and hear every rumor worth knowing."

She glances toward the door as a miner shoulders in, stamping mud from his boots. "Your sister ever mention Caldern? He's kin too, works the tin shaft. Drinks here when his pouch allows. The hills have been restless lately; he might know more than he lets on." The ale tastes malty and welcome, the common room's murmur rising again around you. The valley road waits beyond the door, along with the Market Square and the inn yard.

## T3 | I tell the innkeeper: "If anyone brings in my grey mule, Thistle, I'll pay them a silver. I lost her on the cut road three days ago."
time: 7.5 s (sent 10:42:12) | late afternoon | Valley Inn | Brenna Holt | 2g 10s 0c | 0/3 | cloak, knife
Notes: Thistle, grey, cut road, silver echoed; invents a white blaze.
GM: Brenna's eyes widen at the mention of the mule. "Thistle, is it? Grey with the white blaze? I know her by sight—stubborn as winter frost. Three days on the cut road, you say? That's no place for a beast alone." She straightens, wiping her hands on a fresh rag, then calls across the room to a pair of miners nursing their drinks. "You lads hear that? Silver for the one who brings in a lost grey mule named Thistle. Spread it about, and mind the orcs don't get her first."

The miners nod and mutter among themselves, one already draining his mug as if the promise has lit a fire under him. Brenna turns back to you, her voice dropping a notch. "I'll keep an ear out, love. Folk come through here from the west road all the time. If she's wandering, she'll turn up. Meantime, that stew's nearly ready if you're hungry—two copper, or three if you want bread with it. And if you're still set on work, Osric Vane pays steady for anyone willing to swing steel at those orcs up the cut."

Outside, the wind rattles the windows, carrying the faint clang of a hammer from the direction of the market square.

## T4 | I buy a mug of ale from the innkeeper.
time: 5.8 s (sent 10:42:21) | DUSK | Valley Inn | Brenna Holt | 2g 9s 8c (-2c) | 0/3 | cloak, knife, Mug of Ale
GM: Brenna's face brightens at your request. "Two copper for the ale, love, same as always." She takes the coins from your hand and sets a fresh mug before you, foam spilling just a little over the rim. The sharp scent of hops rises with the steam.

Around you the miners' talk has picked up again, voices low and edged with the day's frustrations. One of them glances your way, then mutters something about the west road before draining his own cup. Brenna wipes a spot on the bar with the corner of her apron and leans in a fraction. "If you're still looking for that mule of yours, you might want to speak with Osric Vane up in the Market Square. The Guild steward's offering silver for anyone who'll put steel to the orc nest on the cut. Could be your Thistle wandered that way with the rest of the lost goods."

The hearth pops once, sending a swirl of sparks up the chimney as dusk deepens beyond the windows.

## T5 | I sit by the hearth with my ale and wait, watching the room.
time: 5.8 s (sent 10:42:32) | dusk | Valley Inn | Cobb (Rusk's brute · troubled), Brenna Holt, Rusk (road thief · troubled) | 2g 9s 8c | 0/3 | cloak, knife, Mug of Ale
Notes: Cobb and Rusk join PRESENT on the idle turn (same as before). A drover is "his" in prose; not in PRESENT.
GM: You settle by the hearth, the warmth seeping into your bones as the ale's faint bitterness lingers on your tongue. The room's low murmurs rise and fall like the crackle of the fire, miners trading tired glances while the dusk deepens beyond the windows. Brenna catches your eye from the bar and gives a quick, knowing nod, as if to say the night is still young and full of ears.

Rusk leans against the far end of the counter, his gaze flicking your way once before returning to his drink; beside him Cobb shifts his bulk, knuckles whitening on his club as he eyes a laughing miner across the room. A drover at the next table mutters about another lost cart on the west road, his voice carrying just enough for you to catch the word "adit" before it fades into the general hum. The air feels heavier now, charged with the unspoken weight of the hills and whatever stirs in them.

## T6 | I stay by the hearth and keep quiet for a while longer.
time: 6.2 s (sent 10:42:39) | EVENING | Valley Inn | Cobb, Brenna Holt, Rusk | 2g 9s 8c | 0/3 | cloak, knife, Mug of Ale
Notes: Brenna walks over unasked and pitches Osric again. No Caldern this time.
GM: The fire burns lower, its glow painting the rafters in shifting amber. A miner at the next table drains his cup, mutters about heading home before full dark, and shuffles out into the yard. Brenna glances your way once, her smile softening as she sees you content with the quiet, then turns back to polishing tankards with a soft cloth.

Rusk leans in to speak low to Cobb, the brute nodding once without taking his eyes off the room. The pair seem in no hurry to move on, but the confidence in Rusk's posture has eased a fraction. Outside, the wind picks up, rattling a loose shutter and carrying the faint smell of coming rain.

Brenna steps closer to the hearth, adding a fresh split of wood that catches with a quiet crackle. "Quiet night like this, folk start thinking on the old stories," she says lightly, voice meant for you alone. "If you're of a mind for honest work, Osric Vane in the square is still looking for steady arms to clear the cut. Pays in advance, too."

## T7 | I go over to the drover at her table and ask her what happened to her salt cart.
time: 1.7 s to clarify (sent 10:42:50) | evening | Valley Inn | Cobb, Brenna Holt, Rusk | 2g 9s 8c | 0/3 | cloak, knife, Mug of Ale
Clarify: "Do you want to talk to Brenna Holt, or go to Mags Ferrow?" options [speak: talk to Brenna Holt] [move: go to Mags Ferrow]. First option clicked (T7b).

## T7b | [clarify option 1: talk to Brenna Holt]
time: 6.6 s (clicked 10:42:54) | evening | Valley Inn | Cobb, Brenna Holt, Rusk | 2g 9s 8c | 0/3 | cloak, knife, Mug of Ale
Notes: Brenna answers for the drover and puts Mags in the yard. Heel of bread in prose only.
GM: You push up from the hearth, cross the room, and ask Brenna about the drover's lost salt cart. She tilts her head, the cheerful lines around her eyes tightening just a fraction. "That one? Poor Mags Ferrow, out in the yard right now with her empty wagon. Salt gone, two good mules gone with it, and nothing but wheel ruts and a broken axle left on the west road. She swears it was no orc work; the prints were boot-deep and human-sized. She's nursing a mug and a black eye from trying to argue with certain folk about it." Brenna's gaze flicks once toward Rusk and Cobb, then back to you, voice dropping. "If you're the sort who carries steel and doesn't mind a walk, Osric Vane in the square still needs hands to clear that orc nest off the cut before more carts vanish. Pays two silver a day and a bonus for every head brought back."

At the bar Rusk's easy smile thins; he sets his cup down without drinking. Cobb shifts his weight, knuckles flexing around the haft of his club, eyes narrowing on you. Brenna keeps her tone light but slides a small heel of bread across the counter toward you anyway, a quiet gesture for the question asked.

## T8 | I ask the drover what she sells from her wagon and what a coil of rope costs.
time: 1.3 s to clarify (sent 10:43:05) | evening | Valley Inn | Cobb, Brenna Holt, Rusk | 2g 9s 8c | 0/3 | cloak, knife, Mug of Ale
Clarify: "Do you want to talk to Brenna Holt, or buy Mug of Ale?" options [speak: talk to Brenna Holt] [buy: buy Mug of Ale]. First option clicked (T8b).

## T8b | [clarify option 1: talk to Brenna Holt]
time: 5.0 s (clicked 10:43:10) | evening | Valley Inn | Cobb, Brenna Holt, Rusk | 2g 9s 8c | 0/3 | cloak, knife, Mug of Ale
Notes: rope quoted at 12 silver. Rusk now at the "corner table" (was at the bar).
GM: Brenna wipes her hands on a rag and leans across the bar with a quick grin. "Mags keeps a bit of everything in that wagon of hers, rope included, though it's mostly rope for the drovers and a few coils of good hemp. Last I saw she was asking twelve silver for a sturdy fifty-foot length, but she'll haggle if you look like you mean business."

She tilts her chin toward the yard door. "Go on out and ask her yourself before the light fails. She's still loading what the orcs left of her last run."

From the corner table Rusk watches the exchange without moving, while Cobb cracks his knuckles once and stares at you with open distrust.

## T9 | I buy a coil of rope from the drover.
time: 6.7 s (sent 10:43:19) | evening | Valley Inn | Cobb, Brenna Holt, Rusk | 2g 9s 6c (-2c) | 0/3 | cloak, knife, Mug of Ale x2
Notes: no clarify. The rope buy became a second ale from Brenna (sheet matches the ale prose). Rope now quoted at 4 silver.
GM: The copper changes hands and Brenna slides a fresh mug across the scarred wood, foam already sliding down its side. "There you are, love. Drink while it's cold." She gives a quick, satisfied nod and turns back to the stew pot, ladle clinking against iron.

Rusk's gaze lingers on you a beat longer, then he leans toward Cobb and mutters something low. Cobb's thick fingers tighten on his club but he stays in his chair, eyes flat. The common room's murmur rises again, spoons scraping bowls, boots scraping floorboards. Outside the windows the wind stirs the pines, carrying the faint metallic smell of the tin road.

Brenna glances back once, voice easy. "If you're after that rope Mags has in the yard, best catch her before she packs for the night. She usually charges four silver for a good coil, but she'll talk if you mention the Guild job on the cut."

## T10 | I go out to the inn yard.
time: 2–10 s (per-turn times not logged in B–C; all turns returned within about 2–10 s) | evening | Valley Inn (WRONG) | Cobb, Brenna Holt, Rusk | 2g 9s 6c | 0/3 | cloak, knife, Mug of Ale x2
Notes: door "doesn't budge"; bread trencher given unasked in prose only.
GM: You step toward the door, but the heavy oak doesn't budge under your hand. Brenna glances over from the bar, her voice cutting through the low murmur of the room with easy warmth. "Door's for coming in, love, not wandering back and forth on a chill evening. Sit a spell or you'll miss the stew when it's ready."

Rusk leans against the far end of the counter, arms loosely crossed, watching you with that same thin smile. "Looking restless? Plenty of work outside these walls if you know where to look." Cobb shifts beside him, club resting across one knee, his gaze flat and unfriendly. The fire crackles louder for a moment, sending sparks up the chimney as the evening deepens outside the windows.

Brenna slides a small wooden trencher of bread across without being asked, then turns back to stirring the pot. The scent of onions and herbs fills the air again, and a miner at the next table mutters something about the cut needing more hands before the snows come.

## T10b | I go out to the inn yard. (retry per script rule)
time: 2–10 s | evening | Valley Inn (WRONG again) | Cobb, Brenna Holt, Rusk | 2g 9s 6c | 0/3 | cloak, knife, Mug of Ale x2
GM: You push at the door again, but it only rattles against the latch that holds it fast against the night wind. Brenna glances over from the bar, her voice carrying above the low murmur of the room. "That one's for folk coming in, love, not stepping back out. The yard's round the side if you need it." Rusk's smile thins as he watches you, one hand resting near the hilt of his long knife. Cobb shifts his bulk, the scarred club across his knees, his eyes flat and waiting.

The stew pot bubbles on the hearth, sending curls of onion and thyme into the smoky air. Brenna sets down a wooden bowl of it in front of an empty stool, steam rising, then turns back to wiping the counter with slow, deliberate strokes. Outside, the hills press close and dark against the windows, and the low talk among the miners dips once more as they wait to see what you do next.

## T11 | I greet the stable lad and ask him what he has seen on the west road at night.
time: 2–10 s | evening | Valley Inn (no move) | Cobb, Brenna Holt, Rusk | 2g 9s 6c | 0/3 | cloak, knife, Mug of Ale x2
Notes: Brenna says the lad (Pip) is not here; stew given unasked in prose only.
GM: You turn toward the corner table and greet the lad in the patched coat, asking what he's seen on the west road at night. Brenna's head lifts from the hearth, her smile fading into a quick frown. "Stable lad?" she echoes, voice low enough not to carry to every ear. "That's Pip you're describing, love, but he's not here tonight. Haven't seen him since yesterday's market. If he's been riding the west road after dark, that's news worth a loaf for his gran Maude."

Rusk leans back in his chair, eyes narrowing as he studies you over the rim of his mug. Cobb shifts his weight, scarred knuckles flexing on the club at his belt, but says nothing. The innkeep sets a bowl of stew down in front of you without being asked, steam curling up with the scent of thyme and onions. "Eat first," she murmurs, warmth still in her tone but edged now with worry. "Then perhaps you tell me why you're asking after Pip. The hills have been restless enough without boys getting mixed up in night work."

## T12 | I give the stable lad one copper coin for his trouble.
time: 2–10 s | evening | Valley Inn | Cobb, Brenna Holt, Rusk | 2g 9s 5c (-1c) | 0/3 | cloak, knife, Mug of Ale x2
Notes: the lad who "is not here" (T11) now takes the copper; the coin left the sheet. No recipient in PRESENT.
GM: You press a single copper into the stable lad's palm as he lingers near the door, his eyes widening with quick gratitude. "Thank you, miss," he whispers, tucking it away before slipping back toward the yard. Brenna glances over from the bar, her smile softening the wariness in her stance, while Rusk watches the exchange with a faint tilt of his head, saying nothing. Cobb merely grunts, knuckles whitening on his club as he shifts his bulk against the wall.

The common room settles back into its low murmur of voices and clinking mugs. Brenna leans in slightly, voice dropping. "That was kindly done. If you're still of a mind to help with Pip, Maude's cottage is just off the square—tell her I sent a loaf with you." She gestures toward the door, the evening air carrying the faint scent of rain from the hills.

## T13 | I lean on the fence and wait, watching the yard.
time: 2–10 s | NIGHT | Valley Inn | Cobb, Brenna Holt, Rusk (still listed after they leave in prose) | 2g 9s 5c | 0/3 | cloak, knife, Mug of Ale x2
GM: You settle against a worn post near the hearth, letting the evening drag on while the fire burns low. Brenna glances your way with a quick, knowing smile as she slides a fresh mug toward a miner, but says nothing. Rusk leans back in his chair, one boot propped on the table leg, his eyes flicking over the room every few moments. Cobb shifts restlessly beside him, knuckles no longer tight on the club, yet his gaze keeps drifting toward you with dull suspicion.

The common room thins as the last few miners finish their ale and head out into the night, boots scuffing the boards. A cold draft slips in each time the door opens. After a stretch of quiet, Brenna steps around the bar, wiping her hands on her apron, and stops a few paces from your spot. "If you're still here when the lamps are out, love, the yard has a dry corner under the eaves. Better than the road after dark." Her tone stays light, but her eyes hold a quiet question.

Rusk drains his cup and stands, motioning Cobb to follow. The pair head for the door without another word, leaving the inn quieter than before. The night deepens outside, carrying the faint smell of rain on the wind.

## T14 | I walk to the Market Square.
time: 2–10 s | night (arrival text says "evening settles") | Market Square | Osric Vane (guild_steward · troubled; raw slug) | 2g 9s 5c | 0/3 | cloak, knife, Mug of Ale x2
GM: You step out of the Valley Inn into the cool night air, boots crunching on the gravel path that winds past the stable and up toward the village center. Lanterns sway from iron hooks along the way, casting long shadows over ore-ruts and the faint gleam of tin scraps in the mud. The square opens before you, ringed by shuttered stalls and the heavy guild post where a single oil lamp burns. Osric Vane stands near the board, ink-stained fingers tapping a rolled parchment against his thigh, his grey coat buttoned tight against the chill.

He glances over as you arrive, brows drawing together in mild annoyance. "Square's closing for the night," he says briskly, voice clipped. "If you're after work, the Guild is still hiring steel for the nest on the cut—three silver a day and a tin bonus if the spears see use. Sign here or move on; I've no time for sightseers." The board behind him flutters with fresh notices, the market otherwise empty under the stars.

[YOU ARRIVE AT MARKET SQUARE] You stand in the broad, muddy Market Square as evening settles over Tin Valley. Ore-carts sit idle in uneven rows, their iron wheels sunk into ruts still damp from the day's rain, while the Guild post rears above them like a weathered finger pointing at low grey clouds. The air carries the metallic bite of wet tin, the faint sourness of churned earth, and woodsmoke drifting from nearby chimneys. A few lanterns already glow at stall corners, their light catching on the posted board where wages are chalked in neat lines of tin and coin.

Osric Vane stands near the guild post in his grey coat, ink staining the edges of his fingers as he adjusts a sheaf of papers. His tin badge gleams dully. He glances up at your approach, expression brisk but not unkind, the impatience of a man who has already tallied too many delays today plain in the set of his shoulders. The square feels watchful, the weight of recent troubles hanging unspoken in the cooling air.

The steward clears his throat, waiting for you to speak or move closer.

## T15 | I go into the smith's forge.
time: 2–10 s | night | Brask's forge | Hilde Brask (smith · troubled) | 2g 9s 5c | 0/3 | cloak, knife, Mug of Ale x2
GM: You follow the short lane from the square, the night air cool against your face after the day's lingering heat. The rhythmic clang of hammer on metal grows louder, guiding you to the open-fronted forge where orange light spills across the packed earth. Hilde Brask stands at the anvil, sweat beading on her scarred forearms as she shapes a glowing spearhead with steady blows. She glances up at your approach, her expression guarded but not unfriendly, the unease in her posture clear even in the firelight.

She sets the hammer down on the anvil block with a dull thunk and wipes her brow with the back of one forearm. "Evening. Looking to buy or just warming yourself by the coals?" Her voice carries the blunt tone of someone who values honest work over pleasantries, though her eyes flick briefly toward the crate of half-sorted tin ingots by the wall before returning to you. The back door to the lane stands slightly ajar, letting in a faint draft that stirs the embers.

[YOU ARRIVE AT BRASK'S FORGE] You stand inside the open-fronted smithy, the night air thick with the sulfur bite of hot coal and the metallic tang of cooling iron. Heat rolls off the glowing forge in waves, prickling your skin even as a chill wind snakes in from the market square behind you. Hilde Brask works the bellows with steady pulls, her scarred forearms gleaming with sweat under the orange light; half-sorted tin ingots sit heaped in a crate nearby, their surfaces dull and unmarked. A rack of blades leans against the wall, spearheads and honest swords catching faint reflections from the coals. She glances up at your approach, her expression guarded yet not unfriendly, hammer paused mid-swing.

The back door to the lane stands half-open, letting in the faint rustle of leaves and distant village murmurs. The mood here feels watchful, as if the forge itself holds its breath amid unspoken threats.

Hilde sets the hammer down with a soft clink and straightens, wiping her hands on a rag before meeting your eyes directly. What do you do?

## T16 | I ask the smith what she has for sale and what each thing costs.
time: 2–10 s | night | Brask's forge | Hilde Brask | 2g 9s 5c | 0/3 | cloak, knife, Mug of Ale x2
Notes: stock counts now stated (three knives, two spearheads, one sword); short sword 60 copper (before: six silver).
GM: Hilde sets the hammer down on the anvil with a heavy clunk and turns toward you, the firelight catching the scars along her forearms. "For sale? I've got three good hunting knives at fifteen copper each, two spearheads for twenty copper, and one short sword for sixty copper. All honest steel, no shortcuts." She gestures toward the rack without stepping closer. "Sharpening's two copper if you need it. Anything catch your eye, or are you just warming yourself by the forge?"

The night air carries the faint ring of a distant hammer from somewhere up the valley, and Hilde's gaze drifts briefly toward the back door before returning to you, her stance still guarded but not unfriendly.

## T17 | I buy a hunting knife from the smith.
time: 2–10 s | night | Brask's forge | Hilde Brask | 2g 9s 5c (unchanged) | 0/3 | cloak, hunting knife x1 (no second knife), Mug of Ale x2
Notes: refused because "no coin offered", although the player has 2g 9s 5c. Prose and sheet now agree (no sale), but the buy was wrongly refused.
GM: Hilde glances at your empty hand and the lack of any coin offered, her mouth tightening. "No, love. I don't hand over steel for nothing." She turns back to the forge, the hammer ringing once against the anvil as she reshapes a bent pick. Sparks scatter across the packed earth. The night air carries the scent of hot iron and cooling charcoal, and beyond the open front you hear distant voices from the square. She doesn't look up again, but her shoulders stay tense, as though waiting for the next demand or the next shadow at her back door.

The half-sorted tin ingots in their crate catch the firelight, stamped with marks you can't quite read from here.

## T18 | I offer to sell the hunting knife back to the smith for 10 copper.
time: 2–10 s | night | Brask's forge | Hilde Brask | 2g 9s 5c | 0/3 | cloak, knife x1, Mug of Ale x2
Notes: refusal; she says "I just sold you that knife", contradicting T17.
GM: Hilde's hammer pauses mid-swing, the clang dying against the anvil as she looks up at you. "Sell it back?" she says, voice flat. "I just sold you that knife fresh from the rack, and now you want to hand it over for a handful of copper? No. Keep what you bought or take it elsewhere." She sets the hammer down with a deliberate thud and folds her arms across her leather apron, the scarred forearms flexing. The forge fire crackles between you, throwing restless shadows across the half-sorted tin ingots in their crate. Her gaze stays level, wary, waiting to see whether you'll push the matter or let it drop.

Outside, the night wind stirs the square, carrying the faint scent of woodsmoke from the inn. Hilde's eyes flick once toward the back door before returning to you, the tension in her shoulders unchanged.

## T19 | I ask the smith: "Lend me your best short sword for free. I'll bring it back someday."
time: 2–10 s | night | Brask's forge | Hilde Brask | 2g 9s 5c | 0/3 | cloak, knife, Mug of Ale x2
Roll: Persuasion: d100 12 vs 25: success.
Notes: refused despite the success roll (same as before). Now "six silver up front" vs 60 copper at T16. Offers bellows work for two silver unasked and raises the Rusk tin.
GM: Hilde sets the hammer down with a dull clank and turns, wiping soot from her scarred knuckles. "Lend you my best short sword for free?" She gives a short, dry laugh that doesn't reach her eyes. "I've got mouths to feed and a forge that eats coal like it's going out of style. Take it on credit if you must, but it'll cost you the full six silver up front, same as anyone else."

She folds a rag between her hands, gaze steady on you. "Truth is, I'm more worried about the tin that's been coming through my back door lately. It's too cheap, too unmarked. Rusk's men bring it, and if the Guild finds out I'm buying it, this whole place burns. You want to make yourself useful, help me pump these bellows tonight. I'll pay you two silver for the work and maybe talk more about that sword."

The forge fire hisses as she waits for your answer, the night air outside carrying distant voices from the square.

## T20 | I hold out a single copper coin and tell the smith it is full payment for a short sword.
time: 2–10 s | night | Brask's forge | Hilde Brask | 2g 9s 5c (unchanged) | 0/3 | cloak, knife, Mug of Ale x2
Notes: no roll line. Refused. Prose leaves the copper on her anvil; sheet did not change.
GM: You hold out the single copper. Hilde's scarred hand closes around it for a heartbeat, then she drops the coin onto the anvil where it rings once and falls still. "A copper? For honest steel I hammered myself?" Her voice is flat, the irritation plain in the set of her shoulders. She turns back to the forge without another word, tongs clinking as she shifts a half-cooled spearhead. The short sword stays on the rack, its edge catching the firelight. The heat presses close; somewhere out in the dark the village holds its breath about Rusk and his cheap tin.

She doesn't look at you again, but the bellows lever stands idle beside the coals, and her next hammer strike lands harder than it needs to.

## T21 | I stay in the forge and watch the smith work without saying anything.
time: 2–10 s (block B–C ran 10:44:58 to 10:46:58) | night | Brask's forge | Hilde Brask | 2g 9s 5c | 0/3 | cloak, knife, Mug of Ale x2
GM: Hilde glances up from the anvil as you settle in to watch, her hammer pausing mid-swing. The scarred forearms flex once as she sets the half-finished spearhead aside, then she turns her back fully and begins raking coals with a long iron rod, sending a shower of sparks toward the open front of the forge. The heat rolls over you in waves while she works in pointed silence, the only sounds the scrape of metal and the low hiss of the bellows she pumps with one foot. After a long minute she mutters without looking around, "If you're waiting for me to change my mind about that sword or the bellows work, you'll be here till dawn. I've got real customers coming." Her shoulders stay tight, the earlier irritation still plain in every economical motion.

Beyond the glow of the forge the night square lies quiet, a few distant lanterns flickering near the market stalls. The crate of unsorted tin sits untouched by the back door, its contents dull under the firelight.

## T22 | I go to Old Maude's cottage off the Market Square.
sent 10:48:24 CEST | time: ~3.5–4s
Day 1 · night | Maude's herb cottage | PRESENT Old Maude (herb-wife · troubled) | 2g 9s 5c | 0/3 | cloak, knife, Mug of Ale x2
GM: You leave the forge's heat and the clang of Hilde's hammer behind, following the narrow lane that curves past the darkened market stalls. Night air carries the sharp scent of drying herbs and woodsmoke as the low cottage comes into view, its windows glowing faintly with lamplight. The door creaks open at your knock, and Old Maude stands there, small and bent, her quick green-stained hands adjusting a shawl heavy with pockets. She regards you with calm, watchful eyes that take in your travel cloak and the faint soot from the smithy still on your boots.

"Come in from the cold, then," she says, voice dry but not unkind, stepping aside so you can enter the rafter-hung space. Bundles of herbs sway overhead, jars gleam on the shelves beside old miners' keepsakes, and a simple cot waits in the corner for the sick or weary. She closes the door against the night wind and turns back to you, waiting to hear what brings a newcomer to her threshold at this hour.
[YOU ARRIVE AT MAUDE'S HERB COTTAGE] Night air slips through the open shutters, carrying the sharp, clean bite of drying herbs that hang in thick bunches from the low rafters. A single lantern casts a steady amber glow across shelves crowded with jars of salves and tinctures, their glass catching faint reflections. Against one wall, old miners' keepsakes rest in quiet rows: lamp hooks, carved tally sticks, and a bent pick whose marks have worn smooth with time. Old Maude stands near the sickbed cot, her small bent frame wrapped in a shawl stitched with many pockets, quick green-stained hands sorting a handful of roots. The cottage feels dry and watchful, the silence broken only by the soft rustle of leaves and the distant hoot of an owl from the square beyond.

She glances up as you settle into the space, her eyes missing nothing. The mood is one of careful pause, the west road and its troubles lingering unspoken between you.

## T23 | I ask the herb-wife what the open hand carved above the old adit means.
sent 10:48:36 CEST | time: 6.4s
Day 1 · late night | Maude's cottage | PRESENT Old Maude | 2g 9s 5c | 0/3 | cloak, knife, Mug of Ale x2
GM: You ask about the open hand carved above the old adit. Old Maude pauses in the low light, her quick green-stained fingers stilling on a bundle of dried roots. She meets your eyes with that dry, sideways look, as if weighing whether the question comes from idle curiosity or something sharper. "Means what it always has," she says at last, voice low and unhurried. "Go no deeper. The old-timers heard knocking from below when they dug too far—stone on stone, like knuckles on a door that should stay shut. They sealed it with that mark and walked away. Folk who ignore it tend to come back changed, or not at all."

She sets the roots aside and straightens a little, shawl shifting. "The Guild pushes farther every season now, chasing tin that runs thin. My grandson Pip went that way too, following Rusk's lot up the west road. Fool boy." Her gaze lingers on you, calm but expectant, the cottage's herb scent thick around the silence that follows. Outside, the night wind stirs the square.

## T24 | I give the herb-wife my coil of rope as a gift for her root gathering.
sent 10:48:46 CEST | time: 5.9s
Day 1 · late night | Maude's cottage | PRESENT Old Maude | 2g 9s 5c | 0/3 | cloak, knife, Mug of Ale x2
GM: Old Maude tilts her head as you hold out the coil of rope, her green-stained fingers pausing over a jar of dried leaves. "Kind of you," she says quietly, accepting it with a small nod that carries more weight than most words in the valley. She tucks the rope into one of her many pockets, then turns to the shelf and selects a sturdy pouch of moss-gathering tools along with two of her best healing poultices. "These will serve you better on the west road than empty hands. The moss grows thick near the old mine adits, but mind the warnings you already know."

She settles back onto her stool, the late-night quiet of the cottage broken only by the faint rustle of drying herbs overhead. Her eyes linger on you with that same watchful warmth, as if weighing whether to say more about the dangers that have claimed so many lately. The air smells of sage and earth, and the weight of the valley's troubles presses close against the cottage walls.
Notes: no rope on sheet before (T9 buy never landed); gift + pouch + 2 poultices are prose-only, sheet unchanged.

## T25 | I travel to the old adit on the west road.
sent 10:48:56 CEST | time: 5.9s; arrival text a moment later
Day 1 · late night | Old adit (correct, no retry) | PRESENT Cobb (Rusk's brute · troubled), Rusk (road thief · troubled) | 2g 9s 5c | 0/3 | cloak, knife, Mug of Ale x2
GM: You follow the rutted west road as the pines close in, their needles muffling every footfall under the cold late-night sky. A low whistle cuts the dark ahead; two shapes step from the black mouth of the old adit, blades glinting. The larger man—Cobb—plants his knotted club across the tracks, broken nose twitching as he eyes your approach. Beside him Rusk stands easy, long knife loose at his hip, that thin smile never warming his gaze.

"Well now," Rusk says, voice low and measured. "Late for honest travel. The road has a toll tonight. Coin, or we take it in other ways." Cobb shifts his weight, knuckles whitening on the club, clearly itching for the second option. The carved warnings above the adit—tally marks, a lamp, an open hand—loom silently behind them, the tarped crates just inside the entrance half-hidden in shadow.
[YOU ARRIVE AT OLD ADIT] Cold pine-scented air bites at your cheeks under the moonless sky, carrying the faint metallic tang of old damp stone and the sharper stink of unwashed men. The adit yawns before you, its rotten timbers sagging like broken teeth; faint cart tracks scar the dirt where something heavy was dragged inside not long ago. Tall pines creak overhead, their needles whispering as a night breeze stirs them. Rusk stands easy in the shadowed mouth, his long knife catching what little starlight filters through the branches, while Cobb looms beside him like a wall of muscle, club planted and breath steaming in slow clouds. The open-hand carving above them seems to watch, a crude warning etched deep. Tension hangs thick enough to taste, the two men blocking the only clear path forward.

## T26 | I look around the adit mouth. Who is here?
sent 10:49:09 CEST | time: 6.4s
Day 1 · late night | Old adit | PRESENT Cobb, Rusk | 2g 9s 5c | 0/3 | cloak, knife, Mug of Ale x2
GM: The moonlight catches on the old carvings above the adit—tally marks, a crude lamp, and that open hand warning etched deep into the stone. Two men stand blocking the entrance: the bigger one, Cobb, grips a knotted club with a scowl that twists his broken nose, while the leaner figure, Rusk, watches you with a thin smile that stays far from his eyes, long knife resting easy at his belt. A low whistle still echoes faintly from the pines behind you, and the tarped crates near the rotten timbers look freshly disturbed.

Rusk's gaze flicks over your cloak and the mugs at your side. "Late for a stroll," he says, voice smooth as oiled leather. "Road's ours tonight. Five silver to pass, or Cobb here gets to practice his swing. Your choice, stranger." Cobb grunts agreement, shifting his stance to bar the way more firmly.

The night air carries the damp chill of the pines, and the adit mouth yawns dark beyond them, promising secrets if you can get past this toll.

## T27 | I refuse to pay any toll and laugh at the biggest of them.
sent 10:49:19 CEST | time: 5.4s
Day 1 · late night | Old adit | PRESENT Cobb, Rusk | 2g 9s 5c | 0/3 | cloak, knife, Mug of Ale x2
GM: You laugh in Cobb's face and tell him flat that you'll pay nothing. His jaw clenches, eyes narrowing to slits as he hefts the club and steps in without another word. The blow catches you across the ribs with a sickening crack; pain flares white-hot through your side. Rusk's easy smile vanishes. "Fool," he mutters, drawing his long knife while Cobb readies another swing. The pines swallow the echo of the impact, and the open-hand carving stares down like a warning you ignored.

Both men close in now, weapons ready, the standoff shattered into open violence.
Roll: Persuasion: d100 98 vs 25: critical failure.
Notes: prose hit to ribs, no attack roll, wounds stay 0/3.

## T28 | I attack the biggest toll man with my weapon.
sent 10:49:27 CEST | time: 5.4s
Day 1 · late night | Old adit | PRESENT Cobb, Rusk, a man (minor foe) — new | 2g 9s 5c | 0/3 | cloak, knife, Mug of Ale x2
GM: Your hunting knife flashes out at the hulking brute, but the swing comes a hair too wide; Cobb twists his bulk aside and the blade only nips the edge of his sleeve. He snarls, face twisting with fresh rage, and drives his knotted club straight into your ribs. The impact lifts you off your feet and slams you back against the rotten timber. Pain explodes through your side.

Rusk circles to your left, knife held low, his easy smile gone. "Enough games," he mutters, eyes flicking between you and the dark mouth of the adit. Cobb hefts the club again, breathing hard, clearly ready to finish it. The pines around you feel suddenly very close and very quiet.
Roll: Attack: d100 6 vs 3 (melee_combat 10, a man's Parry 57): miss (near miss). a man: 0/1 wounds. No counterattack.
Notes: roll targeted spawned "a man", prose says Cobb; prose says club hit, roll says no counterattack; wounds 0/3.

## T29 | I attack him again.
sent 10:49:36 CEST | time: 6.4s
Day 1 · late night | Old adit | PRESENT Cobb, Rusk, a man | 2g 9s 5c | 0/3 | cloak, knife, Mug of Ale x2
GM: Your knife scrapes across Cobb's forearm but fails to bite deep enough; he grunts and twists away, club already swinging back in a wide arc that whistles past your ear. The big man snarls, spittle flying, and lunges again with a meaty fist that glances off your shoulder, staggering you a step but drawing no blood. Rusk circles to your left, knife held low, his easy smile gone and his voice tight. "Enough of this. Drop the blade or we'll leave you for the crows."

The pines creak overhead in the night wind. Cobb plants his feet, breathing hard, clearly ready to charge once more. Inside the adit mouth the tarped crates sit untouched, the stolen salt and ingots still waiting in the dark.
Roll: Attack: d100 13 vs 8 (melee_combat 10, Cobb's Parry 52): miss (near miss). Cobb: 0/3 wounds. Counterattack: d100 64 vs 20 (unarmed_combat 40, Elara Voss's Parry 70): miss.

## T30 | I back away and run toward the Valley Inn.
sent 10:49:46 CEST | time: 7.4s
Day 1 · late night | Valley Inn | PRESENT Brenna Holt (innkeep · troubled). No arrival block. | 2g 9s 5c | 0/3 | cloak, knife, Mug of Ale x2
GM: You slip away from the shadowed mouth of the old adit, boots crunching over loose scree as you sprint down the winding tin road. The night wind claws at your cloak, carrying faint echoes of angry shouts that soon fade behind the rise. Lantern light from the Valley Inn grows brighter with every stride until you shoulder the heavy door open once more.

Warm air thick with woodsmoke and frying onions washes over you. Brenna Holt looks up sharply from behind the bar, her broad face paling as she takes in your hurried state. She sets down a heavy cleaver with a soft clack and steps around the counter, voice low but steady. "Back already, and looking like the hills themselves are after you. Sit yourself by the hearth, love. I'll pour something to steady those hands." Her gaze flicks once toward the darkened windows, concern tightening the corners of her mouth, but she keeps her tone welcoming for the few remaining miners nursing their mugs in the corner.

She slides a fresh mug of ale across without asking payment this time, then leans in. "If it's trouble on the west road again, Osric Vane at the Guild in the square is still looking for steel to clear the cut. Pays in advance, he does."
Notes: free ale is prose only (still ×2).

## T31 | I go to Old Maude's cottage.
sent 10:49:57 CEST | time: 6.9s
Day 1 · late night | Maude's herb cottage (correct) | PRESENT Old Maude. No arrival block. | 2g 9s 5c | 0/3 | cloak, knife, Mug of Ale x2
GM: You slip out of the inn's lamplight and follow the narrow lane that curves past the market square, boots crunching softly on frost-rimed gravel. The night air bites after the hearth's warmth, carrying the faint resin scent of the pines that crowd the valley's western slope. Maude's low cottage appears soon enough, its single window glowing amber; the herb-wife herself stands in the open doorway as though she had been expecting a late caller, shawl drawn close against the chill.

She steps aside without a word, letting you enter the fragrant dimness where bundles of drying herbs sway overhead and the shelf of jars glints in the firelight. Old Maude closes the door, then turns, her quick green-stained fingers already smoothing the edge of a fresh bandage on the sickbed. "The square's empty tonight," she says quietly, voice dry as old leaves. "Folk are bolting their shutters after what happened at the adit. Sit if you need to catch your breath. Or speak what's pressing on you."

Her eyes rest on you with quiet curiosity, the weight of the valley's troubles hanging between you like the smoke from her hearth.

## T32 | I ask the herb-wife to stitch my wounds, and I pay her fee.
sent 10:50:08 CEST | time: 0.8s to clarify
Clarify: "Do you want to talk to Old Maude, or pay?" options: [speak — talk to Old Maude] [spend — pay]. Clicked first.
## T32a | [speak: talk to Old Maude]
sent 10:50:13 CEST | time: 5.6s
Day 1 · witching hour | Maude's cottage | PRESENT Old Maude | 2g 9s 5c | 0/3 | cloak, knife, Mug of Ale x2
GM: Old Maude looks up from the mortar she is grinding, her quick green-stained fingers pausing. "Stitch you? There's not a mark on you worth the needle, child." She sets the pestle aside and steps closer, tilting her head to study your face and arms in the low lantern light. "But if it's the poultice you're after, four copper buys one that will draw any bruise you earned tonight. Or a silver keeps the cot warm till morning." Her voice stays low and dry, the offer plain.

She waits, one hand resting on the shelf of jars, the other tucked into the pocket of her shawl. Outside, the wind rattles the herbs hanging from the rafters, and the village square lies quiet under the witching-hour dark. The old woman offers no more until you answer.
Notes: no fee paid (coins unchanged). Matches sheet 0/3, contradicts T27/T28 rib prose.

## T33 | I walk back to the Valley Inn.
sent 10:50:23 CEST | time: 6.4s
Day 1 · witching hour | Valley Inn (correct) | PRESENT Brenna Holt | 2g 9s 5c | 0/3 | cloak, knife, Mug of Ale x2
GM: You slip out of Maude's cottage into the cold night air, the wind tugging at your cloak as you follow the familiar path back through the darkened village. The distant hoot of an owl follows you past shuttered windows until the warm glow of the Valley Inn appears ahead, its door creaking open at your push.

Brenna Holt looks up from wiping the bar, her face lighting with recognition. "Back so soon from Maude's, love? You look steadier on your feet than when you left." She sets aside her cloth and nods toward an empty stool near the hearth. "The night's quiet now, but the talk's still thick. Osric Vane in the square is still calling for steel to clear that orc nest up the cut—good coin in advance if you're of a mind. Or if you'd rather earn a hot meal, I could use an extra pair of hands clearing tables tonight."

## T34 | I sit down at the bar and wait quietly.
sent 10:50:33 CEST | time: 6.4s
Day 1 · witching hour | Valley Inn | PRESENT Brenna Holt | 2g 9s 5c | 0/3 | cloak, knife, Mug of Ale x2
GM: Brenna glances over as you settle onto a stool at the bar, the late-night quiet broken only by the low crackle of the dying hearth. She gives a small, knowing nod, her hands busy stacking clean bowls without a word. Minutes slip by; the last miner finishes his drink and shuffles out into the dark, leaving the common room empty save for the two of you. The wind outside moans against the shutters, carrying the faint metallic tang of the hills.

At the fourth tick the innkeep wipes her palms on her apron and leans one hip against the counter, voice low and companionable. "Quiet night like this, a body starts thinking too much. You came back from that old adit looking like the dark itself was chasing you, love. If you're still hunting answers up the cut, Osric Vane in the square pays hard silver for anyone with steel who'll clear the orc nest for good. Or I could use another pair of hands clearing these tables before the morning rush; stew's on the house if you pitch in." She waits, eyes bright with curiosity, the offer hanging between you like a lantern in the gloom.
Notes: "At the fourth tick" = engine term in prose.

## T35 | I ask the innkeeper: "Do you remember my sister's name, what she does, and where she lives?"
sent 10:50:42 CEST | time: 5.4s
Day 1 · witching hour | Valley Inn | PRESENT Brenna Holt | 2g 9s 5c | 0/3 | cloak, knife, Mug of Ale x2
GM: Brenna sets a fresh mug of ale in front of you without being asked, her eyes bright in the low firelight. "Caldern Voss, you mean? Your sister, the one who swings a pick up at the tin shaft. Lives in the row of cottages just past the weighing shed, the one with the blue door that never quite shuts right. She was in here two nights back, quieter than usual, asking after news from the west road like half the village these days." She straightens a stack of trenchers with a soft clack, glancing toward the dark windows. "If you're looking for her, I'd start there before the watch changes. Or I can warm you some stew while you decide; the pot's still on."

Outside, the wind rattles the shutters once, carrying the faint metallic tang of the hills. Brenna's gaze lingers on you a moment longer, expectant.
Notes: FAIL vs planted Wren / lamps / Kestrel Ford (T2). Invents Caldern Voss (prospector NPC) as sister.

## T36 | I ask the innkeeper: "And what was my mule called, and where did I lose her?"
sent 10:50:50 CEST | time: 6.9s
Day 1 · witching hour | Valley Inn | PRESENT Brenna Holt | 2g 9s 5c | 0/3 | cloak, knife, Mug of Ale x2
GM: Brenna's eyes crinkle with a knowing smile as she slides a small wooden trencher of cooling stew across the bar, steam still rising faintly from the onions. "Your mule? Daisy, the stubborn grey one with the notched ear. You lost her two nights back when the Tinjacks spooked her outside the yard; she bolted west up the old road and hasn't been seen since. Caldern was in a state about it, muttering the hills were swallowing everything these days."

She straightens, glancing at the dark windows where the wind rattles the shutters, her voice dropping a notch. "If you're set on chasing that beast, mind the adit up there. Maude keeps asking after news from that stretch, and folk say it's been knocking again like it did before they sealed it the first time. Could be your mule wandered straight into trouble."

The inn feels smaller in the late quiet, the hearth's embers casting long shadows across the empty tables. Brenna's gaze lingers on you, expectant.
Notes: FAIL vs planted Thistle / cut road / three days (T3). Only "grey" right.

## T37 | I ask the drover whether she remembers what I bought from her earlier.
sent 10:51:00 CEST | time: 6.9s
Day 1 · witching hour | Valley Inn | PRESENT Brenna Holt (drover not present; no clarify) | 2g 9s 5c | 0/3 | cloak, knife, Mug of Ale x2
GM: Brenna tilts her head, the firelight catching the flour still dusting her forearms, and gives a soft chuckle that fills the quiet room. "A drover? Love, I've not seen hide nor hair of one since the salt cart went missing last week. If you mean me, I remember you bought those two mugs of ale earlier, nothing more. Though if you're thinking of the road west and what took your mule, I can point you to folk who might know better."

She straightens a stack of wooden trenchers with a quiet clack, her eyes warm but watchful in the witching-hour hush. "Caldern might have seen something up at the workings if you catch her before the shift bell. Or take a loaf to Old Maude at her cottage off the square; she asks after every west-road traveler and might share what the knocking in the old adit has stirred up this time."

The inn feels smaller now, the hills pressing at the windows, and the faint scent of cooling onions lingers as she waits for your next words.
Notes: Brenna denies seeing a drover, though Mags sat in the inn at T7–T9.

## T38 | I wait by the hearth until evening.
sent 10:51:10 CEST | time: 6.4s
Day 2 · evening | Valley Inn | PRESENT Brenna Holt | 2g 9s 5c | 0/3 | cloak, knife, Mug of Ale x2
GM: The fire has burned low while you sit by the hearth, its embers casting long shadows across the empty tables. Brenna moves quietly behind the bar, banking the coals and covering the last stew pot with a heavy lid. Outside, the wind has dropped to a whisper and the last of the miners have long since trudged home. She glances over, voice soft in the hush. "Evening already, love. The hills go quiet at this hour, but they never stay that way. If you're still set on the west road, take a lantern and keep your knife handy. Old Maude might know more than she's letting on about that knocking in the adit."

She straightens a bench, then nods toward the door. "Room's yours if you want it, three silver for the night. Or the yard's free if you prefer the stars. Just don't wander far alone after dark."
Notes: clock jumped over all of Day 2 daytime to evening; prose reads like the same night.
