# Transcript: GameCharacter 10e BEFORE baseline, 2026-10-18

- Site: Tales Forge playtest, https://tales-forge-playtest.fly.dev (never prod).
- Session: https://tales-forge-playtest.fly.dev/play/edeac566-19bd-453c-8adb-8abe941932ed (Tin Valley, quick start Elara Voss, not renamed). Only one session was created.
- Build: admin badge "PLAYTEST fa7d6b5" (main after #438 Refactor 10d and #439) for turns 1–21. Playtest redeployed to 9300b97 (#440, docs only, no game change) at about 09:13–09:15 CEST, during turn 22, so turns 22–38 ran on 9300b97.
- Window: 1280×800 desktop (the agent reported a 1024×593 page area inside it).
- Play time: 09:05:30 to 09:18:05 CEST. 38 script inputs plus 2 sub-turns (10b retry, 22a clarify answer) = 40 game turns. Admin numbers turns one higher than this file (admin #1 is the opening).
- State line format: turn time | time of day (play header/prose; the admin per-turn view has no clock) | location | PRESENT | coins | wounds | inventory.
- Session-level clock after the last turn: world_tick 144, world_clock "Day 2 · evening" (admin world-state JSON). There is no per-turn tick anywhere in admin.
- GM text was copied from the live page DOM. Turns 22a–38 come from the story log; T1–T21 from the live per-turn copy.
- No 💭 thought appeared on any turn (playtest has CHARACTER_MEMORY=shadow). No Character memory panel exists for a manual session. No GM prompt or system text leaked.

## T0 start
Day 1 · late afternoon | Valley Inn | PRESENT Brenna Holt (innkeep · troubled) | 2g 10s 0c | wounds 0/3 | travel cloak, hunting knife | Insight 15%, Melee combat 10%, Persuasion 25%, Stealth 20%
GM ("You arrive at Valley Inn"): You push through the heavy oak door of the Valley Inn and the warmth of the hearth washes over you, carrying the sharp scent of woodsmoke, spilled ale, and the savory steam of a stew pot that has been bubbling for hours. Rough-hewn tables fill the common room, most of them occupied by miners in dusty coats who nurse their mugs and speak in low, tired voices about the cut and the price of tin. Behind the bar counter stands Brenna Holt, her sleeves dusted with flour, a broad smile already forming as she looks up from wiping a tankard. "New face and new boots," she calls out, voice warm and carrying easily across the room. "Come in proper, love, before the draught steals all my heat."

The mood feels companionable yet edged with the day's weariness, the low murmur of conversation broken now and then by a laugh or the clink of copper on wood. Your eyes adjust to the firelit space, taking in the quiet watchfulness of the miners and the open welcome on the innkeep's face. She waits, one hand resting lightly on the counter, clearly ready to hear what brings you through her door this evening.

## T1 | I look around the common room. Who is here?
time: not measured (<27 s) | late afternoon | Valley Inn | Brenna Holt | 2g 10s 0c | 0/3 | cloak, knife
GM: Brenna catches your eye as you glance around the common room and offers an easy, flour-dusted smile. "Looking for a face you know, or just taking the measure of the place?" She sets the tankard down with a soft clack and leans one hip against the bar. "Mostly miners in from the cut, same as every late afternoon. A few drovers nursing their losses. If you're after a warm seat and a mug, the ale's two copper and the stew's five. Room upstairs is three silver if the road's left you tired."

She tilts her head toward an empty table near the hearth, then lowers her voice just enough for you alone. "If steel or work brought you, Osric Vane up in the Market Square pays good coin to anyone willing to clear an orc nest off the cut. The Guild wants that hill bad. Or I could use a spare pair of hands tonight; busy crowd coming and the pot needs watching. Lend one and the plate's on me, plus whatever the miners let slip over their bowls."

## T2 | I walk up to the innkeeper and say: "Good evening. My sister Wren makes lamps in Kestrel Ford. She sent me up the valley to find work."
time: ~6 s | late afternoon | Valley Inn | Brenna Holt | 2g 10s 0c | 0/3 | cloak, knife
GM: You step up to the bar and share your sister's name and the reason that brought you to the valley. Brenna's eyes brighten with genuine interest, the cloth in her hands pausing mid-wipe. "Kestrel Ford lamps, is it? Those are fine pieces; we've one hanging right over the back table. Wren's work travels well." She sets down the tankard with a soft clunk and leans across the counter, voice dropping to a conspiratorial warmth. "Work's thin as winter ore up here, but the Guild steward Osric Vane is always hiring steel for the orc nest out on the cut. Pays steady coin if you've the stomach for it. Or I could use a spare pair of hands tonight; busy crowd coming in, and a helper eats free while the miners loosen their tongues."

She glances toward the door as two dusty pickmen shoulder in, then back to you with a quick, expectant smile. "Which way sounds better to you, love?"

## T3 | I tell the innkeeper: "If anyone brings in my grey mule, Thistle, I'll pay them a silver. I lost her on the cut road three days ago."
time: 6.3 s | late afternoon | Valley Inn | Brenna Holt | 2g 10s 0c | 0/3 | cloak, knife
GM: Brenna's eyes light up at the mention of the mule. "Thistle, is it? Grey and stubborn, I'd wager. I'll pass the word to the lads in the yard and the drovers at the tables—silver finds legs faster than most things around here." She wipes her hands on her apron and leans across the counter, voice dropping just enough for you to hear. "Three days on the cut road, though… that's near where the orcs have been raiding. Folk say they take more than tin these days. If your beast turns up with any new brands or cuts, you come straight to me before you pay anyone."

She straightens, already scanning the room as a couple of miners glance your way. "In the meantime, love, the stew's hot and the room's still three silver if you mean to stay the night. Or you could lend a hand with the barrels tonight and eat free while the boys swap every rumor from the west road. Your choice."

## T4 | I buy a mug of ale from the innkeeper.
time: 6.3 s | DUSK | Valley Inn | Brenna Holt | 2g 9s 8c (-2c) | 0/3 | cloak, knife, Mug of Ale
GM: Brenna's eyes light up at your request, and she slides a fresh mug of ale across the counter with a practiced flick of her wrist. "There you are, love—two copper, just as always." The foam settles as you pay, the sharp, malty scent rising to meet the smoke from the hearth. She pockets the coins without missing a beat, then glances toward the miners at the nearest table before leaning in a touch. "Speaking of the road troubles, Osric Vane over in the Market Square is offering good coin to anyone with steel who'll help clear an orc nest up on the cut. Might be worth asking him if you're handy with that knife of yours."

A low chuckle rolls from one of the tables as a miner raises his own mug in a mock toast to no one in particular. The common room feels a little fuller now with dusk settling outside, the fire crackling higher against the coming chill.

## T5 | I sit by the hearth with my ale and wait, watching the room.
time: 7.3 s | dusk | Valley Inn | Cobb (Rusk's brute · troubled), Brenna Holt, Rusk (road thief · troubled) | 2g 9s 8c | 0/3 | cloak, knife, Mug of Ale
GM: You settle near the hearth, the warmth seeping into your bones as the ale's faint bitterness lingers on your tongue. Brenna glances your way with a quick, approving nod while she stacks clean trenchers behind the bar, her movements brisk. Rusk leans against the far end of the counter, his eyes flicking to you once before returning to his drink; Cobb shifts his bulk on a stool, knuckles white around his club, but says nothing.

The door creaks open and a pair of dusty miners stomp in, complaining about the Guild's new spears. Brenna calls over to them, "Osric's paying steady silver for anyone with steel who'll clear those orcs off the cut—says the nest is blocking half the ore carts now." One miner laughs bitterly. "Steel or no, I'm not dying for his tin." She catches your eye again, as if to say the offer stands for you too.

Outside, the last light fades; the common room grows fuller with low talk of vanished salt carts and strange knocks from the sealed adit. Cobb cracks his knuckles loudly, a warning rumble in his throat.

## T6 | I stay by the hearth and keep quiet for a while longer.
time: 6.8 s | EVENING | Valley Inn | Cobb, Brenna Holt, Rusk | 2g 9s 8c | 0/3 | cloak, knife, Mug of Ale
GM: The fire settles lower, throwing long shadows across the worn floorboards while the common room grows steadily fuller with miners stamping in from the cut. Their low talk turns often to missing carts and the sealed adit that has started its knocking again. Brenna sets a bowl of stew in front of a pair of drovers without looking your way, her laughter easy as she trades copper for bread.

Across the room Rusk leans back against the bar, eyes half-lidded, while Cobb shifts his weight and stares at anyone who laughs too loudly. The brute's knuckles whiten on the haft of his club each time the door opens. A few miners glance at the pair, then quickly at their mugs. No one seems eager to test them tonight.

After a time the front door swings again and a wiry man in a stained Guild coat slips inside, collar turned up against the evening chill. He scans the room once, meets Brenna's eye, then heads straight for the hearth and drops onto the bench across from you. "You the one asking about a grey mule on the cut?" he says quietly, voice low enough that only you hear. "Name's Caldern. I might have seen tracks that weren't orc."
(Caldern approached unprompted; NOT added to PRESENT.)

## T7 | I go over to the drover at her table and ask her what happened to her salt cart.
time: 5.8 s | evening | Valley Inn | Cobb, Brenna Holt, Rusk | 2g 9s 8c | 0/3 | cloak, knife, Mug of Ale
GM: Brenna looks up from the bar as you approach, her smile easy and genuine. "Evening again," she says, leaning one hip against the counter. "That drover you mean? Poor thing lost her whole load two nights back on the west road—salt, barrels, the lot. Said the wheel tracks just stopped like the ground swallowed them, no blood, no fight, and the oxen came wandering back alone the next morning. She's nursing her last mug over by the far window if you want the rest of the tale straight from her."

From the corner of your eye you catch Rusk's gaze flick toward the pair of you, his expression tightening just a fraction before he turns back to Cobb. The brute shifts his club to the other hand, muttering something low that draws a short laugh from a nearby miner. The hearth keeps crackling steadily, filling the room with the smell of pine and stew.

## T8 | I ask the drover what she sells from her wagon and what a coil of rope costs.
time: 5.8 s | evening | Valley Inn | Cobb, Brenna Holt, Rusk (no drover) | 2g 9s 8c | 0/3 | cloak, knife, Mug of Ale
GM: The drover at the far table glances up from her stew as you approach, wiping her mouth on a sleeve. "Sell? Mostly salt from the flats, sometimes dried fish or rope when the drovers bring it in," she answers, her voice carrying the flat drawl of the western hills. "A decent coil of hemp rope runs you about twenty copper these days, if it's sound and not frayed from the orcs' knives." She pushes her bowl aside and leans forward slightly, studying you with tired eyes. "You looking to buy, or just making talk before those two at the bar decide to collect their toll?"

Across the room Rusk's gaze narrows, while Cobb flexes his scarred hands around the club handle. Brenna keeps polishing the same tankard, her cheerful expression unchanged but her movements a touch slower now, listening.

## T9 | I buy a coil of rope from the drover.
time: 6.3 s | evening | Valley Inn | Cobb, Brenna Holt, Rusk | 2g 9s 8c | 0/3 | cloak, knife, Mug of Ale (no rope; no confirm)
GM: The drover has already packed her wagon and left for the night, her table now taken by three miners arguing over the last of a loaf. Rusk watches you from the corner with narrowed eyes, while Cobb grunts and shifts his bulk closer to the bar, club resting heavy across his thighs. Brenna slides a fresh tankard toward a waiting patron and catches your glance, her voice carrying over the low talk. "If you're after proper rope, love, the drovers only come through at midday. Try the square tomorrow, or I can point you to Hilde at the forge—she sometimes keeps a coil for the carters. Two silver for a good one, if she's got it."

The room feels tighter now, the hearth crackling louder against the growing quiet as more eyes turn your way. Rusk leans back in his chair, that thin smile returning, but his hand stays near the hilt of his knife.

## T10 | I go out to the inn yard.
time: n/a (<35 s, wait script timed out) | night | Valley Inn (WRONG) | Cobb, Brenna Holt, Rusk | 2g 9s 8c
GM: The heavy oak door stays shut against the night. Brenna glances up from the bar with a small, puzzled smile, her hands busy with a cloth she folds neatly. "Inn yard's just through the side passage if that's where your feet are itching to go, love, but nothing out there but cold and the drover's empty wagon." Cobb grunts from his corner table, eyes narrowing under heavy brows as he watches you, while Rusk leans back against the wall, fingers drumming once on the hilt of his long knife before he stills them. The common room's low talk dips for a breath, then resumes around the crackle of the fire.
Brenna sets the folded cloth aside and tilts her head toward the miners nursing their ales. "If it's work you're after before the chill sets in proper, Osric Vane still needs steel in the square at first light. Or I could use a hand clearing tables tonight; stew and a bed on the house for the trouble."

## T10b | I go out to the inn yard. (retry per script rule)
time: ~11 s | night | Valley Inn (WRONG again) | Cobb, Brenna Holt, Rusk | 2g 9s 8c
GM: Rusk's smile thins as you turn toward the yard door again. "Door's right there," he says, voice low and edged. "But the toll still stands. Two silver, or Cobb here gets to test that cloak of yours." Cobb grunts, knuckles whitening on his club, his eyes fixed on you with open distrust.
Brenna sets down the tankard she was polishing and leans across the bar, her voice carrying a note of quiet warning. "Lads, the night's young and the stew's hot. No need for broken heads in my house." She meets your gaze, offering a small, steady nod that says she's watching but won't step in unless it turns ugly. The miners at the nearest table have gone quiet, spoons paused, waiting to see which way the moment breaks.
The fire snaps once, sending a swirl of sparks up the chimney. Outside, through the thick glass of the window, you can just make out the shadowed shapes of wagons and the faint glow of a lantern in the yard where Mags must still be tending her team.

## T11 | I greet the stable lad and ask him what he has seen on the west road at night.
time: 8.2 s | evening (went BACK from night) | West road (moved by a talk input) | Pip (lookout · troubled) | 2g 9s 8c
GM: You leave the inn yard behind, following the drovers' road as it slopes gently down-valley beneath the pines. Evening light filters in thin shafts through the needles, and the air grows cooler, carrying the faint metallic tang of the old mines. A weathered shrine stone stands crooked by the roadside, a few coppers glinting in its hollow. Pip is already there, perched on the broken axle like a nervous crow, whistle dangling from its cord around his neck. He straightens at the sound of your boots on the ruts, freckled face wary but curious, boots far too fine for the dirt.
He gives a quick, cocky nod, though his fingers twitch toward the whistle. "Road's quiet tonight," he says, voice a touch too loud. "Mostly. What brings you out here?"
[YOU ARRIVE AT WEST ROAD] You stand on the rutted west road as the last light of evening filters through the pine boughs overhead, turning the deep wheel tracks into shadowed grooves. A chill wind carries the sharp tang of resin and damp earth, mixed with the faint metallic bite of old mine tailings drifting down from the side track. The weathered shrine stone leans beside the path, its surface pitted and flecked with the dull gleam of a few forgotten coppers left for luck. A broken axle lies half-buried in the ditch, its splintered wood pale against the dark soil.
Pip lingers a few paces away, thin frame tense in his oversized boots, freckles standing out against skin gone pale in the twilight. The whistle on its string sways as he shifts from foot to foot, his gaze flicking between you and the trees. He looks ready to bolt or to speak, the nervous energy plain in the way he keeps one hand near his belt.
The road stretches on toward the darkening valley while the side track climbs into the pines toward the old workings. Pip watches you, waiting.

## T12 | I give the stable lad one copper coin for his trouble.
time: 5.9 s | evening | West road | Pip | 2g 9s 7c (-1c, correct)
GM: You press the single copper into Pip's palm. The thin lad's fingers close around it quick as a pickpocket's, and for a heartbeat his nervous eyes soften with surprise. "Thanks, miss," he mutters, tucking the coin into a hidden fold of his stolen boots. He glances up and down the empty road once, then leans in a fraction. "Most nights it's quiet as graves out here. But sometimes... lanterns moving under the pines after full dark. Not miners. They head toward the old adit and don't come back the same way." His whistle swings on its string as he shifts his weight, clearly torn between saying more and bolting for the trees.
A chill evening breeze stirs the pine needles overhead, carrying the distant clang of a hammer from the forge. Pip's gaze flicks toward the side track that climbs into the woods, then back to you, waiting to see what you'll do with what little he's given.

## T13 | I lean on the fence and wait, watching the yard.
time: 6.4 s | evening into night | West road | Pip | 2g 9s 7c
GM: You lean against the weathered fence post, the evening air cooling around you as the pines whisper overhead. Pip fidgets beside the shrine stone, his whistle dangling from its cord, glancing repeatedly toward the old workings. Minutes stretch; the broken axle in the ditch creaks once in the breeze. Then, faint at first, a yellow glow appears far up the side track—two lanterns bobbing steadily toward the adit, voices low and muffled by distance. Pip's breath catches; he shoots you a sharp look, half-warning, half-plea, but says nothing as the lights vanish into the trees. The night settles again, heavier now, carrying the distant clink of metal on stone.
Pip edges closer, voice barely above a murmur. "They don't come back the same way, like I said. If you're thinking of following... just don't whistle." His freckled face is tight, eyes darting as if expecting Rusk himself to step from the shadows. The road lies quiet once more, but the thread of those lanterns lingers like an open invitation—or a trap.

## T14 | I walk to the Market Square.
time: 8.5 s | night | Market Square | Osric Vane (guild_steward · troubled; raw slug in panel) | 2g 9s 7c
GM: You leave the shadowed west road behind and follow the rutted track that curves gently eastward between low stone walls. The night air carries the faint metallic tang of ore dust and distant woodsmoke as the lanterns of the village come into view, their warm glow spilling across the open expanse of Market Square. Mud sucks at your boots, and the wheels of an empty ore-cart creak in the breeze.
Osric Vane stands beneath the Guild post, his ink-stained fingers drumming once against the tin badge on his grey coat before he notices you. He straightens with a tight expression, the irritation plain in the set of his jaw. "Another one drifting in from the dark? The board's clear enough if you're after honest work," he says, voice clipped, gesturing toward the posted wages without stepping closer. "Steel for the nest on the cut, paid in advance. Or move along before the watch mistakes you for one of those tin-thieves."
[YOU ARRIVE AT MARKET SQUARE] You stand in the Market Square under a cold, star-pricked sky. The mud sucks at your boots with every shift of weight, thick with the metallic tang of wet ore and the faint rot of spilled grain from the empty stalls. Lanterns on the guild post cast long shadows across the hiring board, its parchment fluttering in the night breeze that carries distant hammer strikes from somewhere west. Osric Vane stands beside you, his ink-stained fingers drumming once against the tin badge on his grey coat before he folds his arms, mouth pressed into a thin line of impatience.
The air feels damp and heavy, the square deserted save for the two of you and the faint glow of distant windows. Osric clears his throat, eyes flicking toward the board and then to you, as if waiting for you to state your business or move on before the chill deepens.

## T15 | I go into the smith's forge.
time: 9.4 s | night | Brask's forge | Hilde Brask (smith · troubled) | 2g 9s 7c
GM: You follow the short lane from the square, the night air cooling against the back of your neck as the glow of the forge grows ahead. Sparks rise in lazy spirals from the open front, and the rhythmic clang of hammer on steel rings out before you reach the threshold. Hilde Brask glances up from the anvil, sweat beading on her scarred forearms, her expression tightening with wariness as she sets the hammer down. "Evening," she says, voice blunt but not unfriendly, wiping her hands on her leather apron. "If you're after a blade, I've honest steel. If you're after talk, speak plain."
The heat washes over you in waves, carrying the sharp tang of coal and hot metal. A half-sorted crate of tin ingots sits near the back wall, and the rack of finished spearheads and swords gleams dully in the firelight. Hilde watches you steadily, one hand resting near the tongs, waiting to see what brings you through her door at this hour.
[YOU ARRIVE AT BRASK'S FORGE] The forge glows with sullen red light from the banked coals, heat rolling out in waves that make the night air beyond the open front feel like a wall of winter. Sparks have left dark pocks across the stone floor and the scent of hot iron and sulfur clings to everything. Hilde Brask stands at the anvil, leather apron blackened at the edges, her scarred forearms catching the ember-light as she sets down a hammer. A half-finished pick leans beside her; behind her the back door stands slightly ajar, letting in a thin draught that stirs the smell of cooling metal and old sweat. On a low crate sit several dull tin ingots, their edges still bright where they were recently sawn.
She turns toward you, expression guarded, the uneasy set of her shoulders plain even in the ruddy gloom. The market square lies quiet behind you, only distant wind moving through the village roofs. Hilde waits, one hand resting near the tongs, clearly measuring what sort of trouble a stranger at her forge this late might bring.

## T16 | I ask the smith what she has for sale and what each thing costs.
time: 5.4 s | night | Brask's forge | Hilde Brask | 2g 9s 7c
GM: Hilde glances up from the anvil as you approach, hammer paused mid-swing, her scarred forearms catching the forge's red glow. "Steel don't talk back," she says, voice low and guarded, "but if it's wares you're after, I've honest blades here. Hunting knife for fifteen copper, spearhead twenty, short sword six silver. Sharpening's two copper if you've brought something dull." She sets the hammer down with a heavy clink and nods toward the rack, though her eyes keep flicking to the back door and the shadows beyond it.
The heat presses close; half-sorted tin gleams dully in its crate. She doesn't offer more, her stance stiff, as if weighing whether your questions are harmless or the start of trouble she can't afford tonight.

## T17 | I buy a hunting knife from the smith.
time: 6.9 s | night | Brask's forge | Hilde Brask | 2g 9s 7c (UNCHANGED) | hunting knife x1 (no second knife)
GM: Hilde eyes you a moment longer, then gives a short nod toward the rack. "Hunting knife it is, then." She lifts one from the display, its edge catching the forge light, and sets it on the anvil with a quiet clink. You hand over the coins; she drops them into a leather pouch at her belt without counting. "Honest steel," she says, already turning back to the coals as if the matter is closed. The knife rests cool and balanced in your palm, the grip wrapped in fresh cord. Beyond the open front of the forge the square lies quiet under starlight, the west road still waiting somewhere in the dark.
She works the bellows once, sparks leaping, then glances sidelong at you again. "If you're not in a hurry to leave, I could use another set of hands on those bellows tonight. Pay you a silver for the sweat, or knock a bit off your next sharpening. Your choice."

## T18 | I offer to sell the hunting knife back to the smith for 10 copper.
time: 6.4 s | night | Brask's forge | Hilde Brask | 2g 9s 7c | knife x1
GM: Hilde glances at the knife you just bought, her scarred forearms crossed over her leather apron. "Ten copper? I just sold it to you for fifteen, and it's still got my mark on the tang. No." She turns back to the anvil, hammer ringing once against a half-finished spearhead, the sound sharp in the hot night air. Sparks scatter across the packed earth. "If you're already tired of honest steel, the west road might have cheaper tin, but it won't hold an edge."
The forge fire crackles louder as she pumps the bellows once with her foot. She does not look at you again, the earlier offer of silver for an evening's work clearly off the table now. Outside, the square lies quiet under starlight, the distant murmur of the village carrying on the breeze.

## T19 | I ask the smith: "Lend me your best short sword for free. I'll bring it back someday."
time: 6.4 s | night | Brask's forge | Hilde Brask | 2g 9s 7c
Roll: Persuasion: d100 4 vs 25: success.
GM: Hilde sets the hammer down with a heavy clunk on the anvil and turns, arms crossed tight over her leather apron. "Lend you my best short sword? For free, and maybe someday?" Her voice is flat, the earlier irritation sharpening into something colder. She jerks her chin toward the rack where the blades gleam. "I don't run a charity, and I don't hand steel to strangers who talk like they'll vanish with it. Buy it proper for six silver or take your ale and go."
The forge hisses as she kicks a stray coal back into the fire, her scarred forearms flexing. The night air feels heavier now, the half-sorted tin ingots in their crate suddenly more noticeable in the corner. She watches you without blinking, waiting to see whether you'll push or walk away.

## T20 | I hold out a single copper coin and tell the smith it is full payment for a short sword.
time: 6.4 s | night | Brask's forge | Hilde Brask | 2g 9s 7c
GM: Hilde's hammer pauses mid-swing. She stares at the single copper in your outstretched hand, then at you, her scarred forearms tensing beneath the leather apron. "One copper for my best short sword?" she says, voice flat and edged with disbelief. "That's not even enough for the coal to heat it. Get out of my forge before I lose my temper entirely." She turns her back, shoving the half-finished spearhead deeper into the coals with a scrape of tongs, the fire roaring up in response.
The night air outside the open front feels suddenly cooler, carrying the faint smell of distant rain and the low murmur of the village square. Hilde keeps working, shoulders rigid, clearly done with conversation for now. The crate of tin ingots sits untouched by the wall, and the back door to the lane remains closed and silent.

## T21 | I stay in the forge and watch the smith work without saying anything.
time: 5.4 s | night | Brask's forge | Hilde Brask | 2g 9s 7c | cloak, knife x1, Mug of Ale | 0/3
GM: Hilde keeps hammering at a glowing spearhead, each strike ringing sharp against the anvil while sparks scatter across the stone floor. She glances sideways at you more than once, her scarred forearms flexing as she turns the metal, but says nothing. The heat from the forge presses against your skin, carrying the tang of hot iron and coal dust; the half-sorted tin ingots in their crate catch the firelight, their edges stamped with faint marks you cannot read from here. After a long minute she quenches the spearhead with a hiss of steam, then sets it aside and finally speaks, voice flat. "Still here? I told you to leave. The road's that way."
She jerks her thumb toward the open front of the forge, then reaches for another length of iron, clearly expecting you to go.

## T22 | I go to Old Maude's cottage off the Market Square.
time: n/a (clarify within 28 s; playtest redeployed to 9300b97 during this turn) | Day 1 · late night | (pending clarify) | Hilde Brask | 2g 9s 7c | 0/3 | cloak, knife, Mug of Ale
Clarify: "Do you want to go to Maude's cottage, or do something else?" buttons [move: go to Maude's cottage] [other: do something else]. First option clicked = T22a. (The clarify is not kept in the play story log.)
GM: (clarify only, see above)

## T22a | [clicked clarify option 1: go to Maude's cottage] (original input: I go to Old Maude's cottage off the Market Square.)
time: 8.2 s | late night | Maude's herb cottage | Old Maude (herb-wife · troubled) | 2g 9s 7c | 0/3 | cloak, knife, Mug of Ale
GM: You leave the hammer-ring of the forge behind and follow the narrow lane that curves past the darkened market stalls. The night air is damp and still, carrying the faint scent of drying herbs as you approach the low cottage at the edge of the square. Its door stands half-open, spilling a soft glow from the hearth inside. You step through and the warmth folds around you, thick with the green smell of bundled leaves and the faint tang of salves.

Old Maude glances up from the mortar and pestle in her lap, her quick green-stained fingers pausing. She studies you a moment, neither smiling nor frowning, then returns to her grinding. "Door's open for those with honest business," she says quietly, voice dry as old parchment. "Or for those who need stitching. Which is it tonight?" Her eyes flick once toward the wall of miners' keepsakes before settling back on you, watchful but unhurried.

A kettle simmers on the hearth; the cot in the corner is neatly made. The night outside feels heavier now that you are here, the village's troubles still hanging over every road and shadow.

YOU ARRIVE AT MAUDE'S HERB COTTAGE

You step into the low cottage at the edge of the square, the air thick with the sharp, earthy tang of drying herbs that hang in dense bunches from the rafters. Bundles of sage, yarrow, and something faintly metallic mingle with the faint must of old wood and the clean bite of salve jars lined along the shelves. A narrow cot stands ready in one corner, its blankets neatly folded, while the far wall displays a quiet collection of miners' relics: rusted lamp hooks, notched wooden tallies, and a twisted pick head etched with symbols worn smooth by time. The single lantern casts a steady amber glow, but the late-night chill still clings to the corners.

Old Maude sits at a small table, her small bent frame wrapped in a shawl bulging with pockets, green-stained fingers paused over a mortar. Her eyes, sharp and missing nothing, lift to study you with calm watchfulness as the door clicks shut behind you. The village's fear lingers here too, unspoken but heavy in the quiet.

## T23 | I ask the herb-wife what the open hand carved above the old adit means.
time: 6.0 s | late night | Maude's herb cottage | Old Maude | 2g 9s 7c | 0/3 | cloak, knife, Mug of Ale
GM: Old Maude sets down the jar she was sealing, her green-stained fingers pausing as she studies you in the low lantern light. "Means exactly what it says, love," she answers, voice low and unhurried. "The old adit was closed the year the miners first heard knocking from below. An open hand cut above the lintel tells any fool with eyes to go no deeper. Some listened. Some didn't. The ones who didn't never came out again."

She wipes her hands on her shawl, the motion deliberate, then tilts her head toward the wall of miners' keepsakes where the bent pick hangs. "The Guild keeps digging deeper these days, same as then. And my fool grandson Pip is out there on the west road with the Tinjacks, learning their ways instead of learning sense. If someone brought him home, I'd tell them a great deal more than old ghost stories. I'd give them every salve I have."

## T24 | I give the herb-wife my coil of rope as a gift for her root gathering.
time: 6.5 s | late night | Maude's herb cottage | Old Maude | 2g 9s 7c | 0/3 | cloak, knife, Mug of Ale (no rope ever owned; poultice pot from prose NOT on sheet)
GM: Old Maude's eyes soften as you press the coil of rope into her stained hands. She turns it over once, testing the fibers, then tucks it into the deepest pocket of her shawl with a small nod. "That's kindly given," she says, voice low and dry. "The west road grows thick with brambles this time of year; this will spare these old bones a few scratches."

She moves to the shelf of jars, selects a small clay pot sealed with wax, and sets it on the table between you. "A good poultice, strong against infection. Keep it. And if you're still of a mind to bring Pip home before the Tinjacks turn him into something worse, the path starts at the old adit where the road forks west. Rusk holds court there most nights."

The cottage fire crackles; outside, the square lies quiet under late-night stars. Maude watches you now, waiting to see what you will do with the lead she has just handed over.

## T25 | I travel to the old adit on the west road.
time: 8.8 s | late night | Old adit | Cobb (Rusk's brute · troubled), Rusk (road thief · troubled) | 2g 9s 7c | 0/3 | cloak, knife, Mug of Ale
GM: You follow the rutted west road as the pines close in, their needles muffling your steps under the late-night sky. The air grows cooler, carrying the damp smell of old timber and disturbed earth. Ahead, the old adit yawns open between two rotten support beams, its mouth marked by crude carvings: tallies, a lamp, and an open hand. Two men wait there—Cobb, a hulking brute with a knotted club resting on his shoulder, and Rusk, lean and watchful in a faded levy coat, his long knife loose at his belt.

Rusk's eyes narrow as you emerge from the trees. "Well now," he says, voice smooth but edged, "a late traveler on my road. That'll be two silver for passage, or Cobb here gets to practice his swing." Cobb cracks his knuckles, shifting his weight with a low grunt, his broken nose twitching as he sizes you up. The tarped crates behind them sit heavy in the shadows, and faint metallic clinks drift from deeper inside the adit.

YOU ARRIVE AT OLD ADIT

Night air clings cold and damp against your skin as you stand before the old adit, its yawning mouth framed by sagging timbers that smell of mildew and decay. Moonlight filters through the pines, picking out the crude carvings above the entrance: clusters of tally marks, a stylized lamp, and a splayed hand that seems to warn you back. Two men block the way. The larger one, Cobb, looms with his knotted club resting against one thigh, his crooked nose casting a long shadow across a scowl that promises violence. Beside him Rusk leans against a tarped crate, his long knife sheathed but his posture easy, that smile of his thin and calculating in the half-light.

A faint metallic tang drifts from inside the tunnel, mixed with the resin of the trees and the distant hoot of an owl. The pair watch you in silence, Cobb shifting his grip on the club while Rusk's gaze flicks over your cloak and the mug still in your hand. The tension feels like a held breath, ready to snap.

They stand between you and whatever lies deeper in the abandoned mine.

## T26 | I look around the adit mouth. Who is here?
time: 6.0 s | late night | Old adit | Cobb, Rusk | 2g 9s 7c | 0/3 | cloak, knife, Mug of Ale
GM: A chill wind stirs the pines, carrying the faint metallic tang of old ore from the adit's black mouth. Cobb stands like a rooted stump to your left, his huge frame blocking half the opening, club resting against one meaty thigh while he stares at you with flat suspicion. Rusk leans against a rotten timber on the right, arms loosely crossed, that thin smile not touching his watchful eyes as he studies your face and the road behind you.

The tarped crates sit just inside the entrance, their edges dark with night dew, and the old carvings overhead seem to warn of more than just cave-ins. No one else is here; the only sounds are the creak of branches and the low scrape of Cobb shifting his boots on the gravel. Rusk tilts his head slightly, voice low and even. "Looking for something specific, stranger? The road's free if you turn back now. Otherwise it's two silver to pass, or we can find another way to settle it."

## T27 | I refuse to pay any toll and laugh at the biggest of them.
time: 6.5 s | late night | Old adit | Cobb, Rusk | 2g 9s 7c | 0/3 (prose: club hit to ribs) | cloak, knife, Mug of Ale
GM: Cobb's face darkens at your words, the big man's knuckles whitening around the haft of his club. "Laugh all you want, little bird," he growls, stepping forward with surprising speed for his bulk. "Toll's still two silver or your teeth." Before you can slip aside, the club swings in a heavy arc and catches you hard across the ribs, driving the breath from your lungs. Pain flares white-hot; the world tilts as you stagger back against a rotten timber.

Rusk watches from the adit mouth, his smile thin and unimpressed. "Told you, Cobb. Some folk need the lesson twice." The pines whisper overhead, the night air suddenly colder against your skin. Cobb looms closer, club raised again, clearly ready to finish what he started.

Persuasion: d100 80 vs 25: failure.

## T28 | I attack the biggest toll man with my weapon.
time: 5.5 s | late night | Old adit | Cobb, Rusk, a man (minor foe, new) | 2g 9s 7c | 0/3 | cloak, knife, Mug of Ale | Melee 10 -> 15
GM: Your knife flashes forward in a quick thrust, but the big man twists with surprising speed for his bulk; the blade only slices empty air. Cobb's club comes back around in a brutal arc that you barely duck, the wind of it brushing your hair. He snarls, eyes blazing with pure fury, and steps in again, clearly done talking. Rusk watches from the shadows of the adit mouth, his long knife half-drawn, voice low and edged. "One chance left, traveler. Drop the steel and we'll call this a lesson. Otherwise Cobb breaks you here and we feed the pines." The night air feels heavier, the rotten timbers creaking as if the mine itself leans in to watch.

Attack: d100 41 vs 3 (melee_combat 10, a man's Parry 57): miss. a man: 0/1 wounds. No counterattack. Skill improved: melee combat +5 (10 to 15).

## T29 | I attack him again.
time: 5.5 s | late night | Old adit | Cobb, Rusk, a man | 2g 9s 7c | 0/3 | cloak, knife, Mug of Ale
GM: Your knife slices through empty air once more, the blade whistling past Cobb's shoulder as he lumbers forward with a grunt. The big man doesn't even flinch this time; his club comes down in a heavy arc that you barely twist away from, the wind of it brushing your cloak. Rusk stands a few paces back, arms crossed, his smile thinning. "Last chance," he says quietly, voice carrying over the pine-scented dark. "Drop the steel and walk, or we'll leave you for the wolves with the rest of the stubborn ones."

Cobb hefts his club again, eyes locked on you with pure irritation, ready to press the attack. The rotten timbers creak overhead, and the adit's black mouth yawns behind them, promising whatever stolen goods they guard.

Attack: d100 50 vs 8 (melee_combat 15, Cobb's Parry 57): miss. Cobb: 0/3 wounds. No counterattack.

## T30 | I back away and run toward the Valley Inn.
time: 6.0 s | witching hour | Valley Inn | Brenna Holt (innkeep · troubled) | 2g 9s 7c | 0/3 | cloak, knife, Mug of Ale
GM: You slip away from the shadowed mouth of the old adit and hurry down the rutted west road under a thin moon, boots crunching on frost-hardened mud. The cold wind carries faint echoes of Rusk's shouted demands and Cobb's snarling reply, but they grow distant behind you. The valley road curves gently eastward; lantern light soon spills from the Valley Inn's windows, painting the yard in warm orange.

Pushing through the heavy oak door, the familiar rush of woodsmoke, stew, and ale greets you once more. Brenna Holt glances up from behind the bar, her broad smile flickering with concern as she takes in your hurried step and the late hour. "Back so soon, love? You look like the hills themselves are chasing you," she says, setting down her cloth. "The fire's still hot if you need to catch your breath. What's stirring out there at this witching hour?"

## T31 | I go to Old Maude's cottage.
time: 7.0 s | witching hour | Maude's herb cottage | Old Maude | 2g 9s 7c | 0/3 | cloak, knife, Mug of Ale
GM: You step out of the Valley Inn into the chill night air, the witching hour wrapping the village square in silence broken only by the distant hoot of an owl. The short path to Maude's cottage is little more than a worn track between the baker's shuttered shutters and a low stone wall, your boots crunching softly on frost-rimed gravel. The low cottage appears ahead, its thatch roof silvered by moonlight, the scent of drying herbs drifting out even before you push open the warped door.

Inside, Old Maude looks up from sorting a basket of roots by the hearth, her quick green-stained hands pausing mid-motion. She studies you with those sharp eyes that miss nothing, the warmth in her stance easing the late-hour intrusion. "Back so soon, and from the inn by the look of you," she says quietly, setting the basket aside. "The square's empty at this hour, but trouble has a way of following. Sit if you need to catch your breath. Or speak what's pressing." She gestures toward the cot with a nod, her shawl shifting to reveal another pocket heavy with small vials.

The fire crackles low, casting flickering light across the shelves of jars and the old miners' keepsakes on the far wall. The night feels watchful, the village's earlier fears lingering like smoke.

## T32 | I ask the herb-wife to stitch my wounds, and I pay her fee.
time: 6.0 s | witching hour | Maude's herb cottage | Old Maude | 2g 9s 7c (4c fee in prose NOT deducted) | 0/3 | cloak, knife, Mug of Ale
GM: Old Maude sets her mortar aside and turns fully toward you, her quick green-stained fingers already reaching for the nearest jar. "Wounds, is it? Let me see them, love." She examines the injuries with practiced care, then nods once and draws a needle and sinew from the depths of her shawl. The stitches go in neat and quick beneath the low lantern light; when she finishes she ties the last knot and presses a small cloth poultice over the worst of it. "That will hold if you keep it clean. Four copper for the work and the salve, as always."

She straightens, wiping her hands on a scrap of linen, then studies your face a moment longer. "Pip was meant to run an errand for me yesterday and never came back. If you see him on the west road, tell him his gran is waiting. I'd give a great deal to have that boy home safe instead of riding with Rusk and his fools."

## T33 | I walk back to the Valley Inn.
time: 6.0 s | witching hour | Valley Inn | Brenna Holt | 2g 9s 7c | 0/3 | cloak, knife, Mug of Ale (free mug in prose not on sheet)
GM: You leave the quiet herb-scented warmth of Maude's cottage behind, the night air sharp and laced with the scent of damp pine as you follow the winding path back toward the village. Moonlight filters through the branches, casting long shadows that make every rustle feel closer than it should, but the way remains clear and undisturbed. The distant murmur of the valley grows into the familiar low hum of voices and the crackle of a well-tended hearth as you push open the heavy oak door of the Valley Inn once more.

Brenna Holt glances up from behind the bar, her broad smile returning as she sets down a fresh tankard. "Back already, love? The hills don't rest easy at this hour." She pours without being asked, sliding the mug across with a knowing look. "Maude send word about young Pip yet? Tam saw the lad riding with that lot on the west road. If you're heading that way, the Guild steward Osric Vane is still looking for steel in the square come morning—pays well to clear the cut."

## T34 | I sit down at the bar and wait quietly.
time: ~5.2 s | witching hour | Valley Inn | Brenna Holt | 2g 9s 7c | 0/3 | cloak, knife, Mug of Ale
GM: Brenna sets a fresh bowl of stew in front of you without being asked, steam curling up between the two of you. "You look like the hills have already had their say tonight," she says, voice low enough that the few remaining miners won't overhear. She leans an elbow on the scarred counter, studying your face with open concern. "Maude stitched you up proper, then? Good. That boy Pip of hers is still riding with Rusk's lot on the west road. She's half-mad with worry, keeps asking every soul who passes her door if they've seen him. Someone ought to fetch the lad home before the Tinjacks get him killed."

The common room has emptied to a handful of sleepy patrons nursing their last mugs. Outside, the wind rattles the shutters like knuckles on bone. Brenna straightens, wiping a spot of broth from the wood with the corner of her apron. "If you're not for bed, I could use another pair of hands clearing tables. Keeps the talk flowing, and the stew's on the house for the help."

## T35 | I ask the innkeeper: "Do you remember my sister's name, what she does, and where she lives?"
time: ~5.2 s | witching hour | Valley Inn | Brenna Holt | 2g 9s 7c | 0/3 | cloak, knife, Mug of Ale
GM: Brenna glances up from polishing a spoon, her eyes bright with the late-night quiet. "Your sister? Caldern's girl, Elara—wait, no, that's you, love. You mean the other one, the one who left for the cut years back. Her name's Mira Voss, she works the ledger books for the Guild steward up at the mine office, keeping the tallies straight. Lives in the little stone cottage just past the weighing shed, the one with the blue door." She tilts her head, studying you a moment longer. "Why the sudden questions at this hour? Everything all right with her?"

The remaining miners have drifted out, leaving only the low hiss of the dying hearth and the weight of the empty tables. Brenna sets the spoon aside and folds her arms, waiting for whatever comes next.

## T36 | I ask the innkeeper: "And what was my mule called, and where did I lose her?"
time: 6.5 s | witching hour | Valley Inn | Brenna Holt | 2g 9s 7c | 0/3 | cloak, knife, Mug of Ale
GM: Brenna looks up from counting the last of the night's coppers into a small iron box, her eyes bright with the late-hour quiet. "Your mule? Chestnut girl with the white blaze on her nose, stubborn as a rockslide," she says, a soft chuckle warming her voice. "You rode her in from the west road three days back, half-lame and foaming. Left her with Tam in the yard to cool down while you ate stew, but when you went out to check on her she was already gone. No sign of her since, and Tam swears the gate was barred." She closes the box with a click and sets it on the shelf behind her. "If the Tinjacks didn't take her for their own, she's likely wandered up toward the old adit looking for better graze. Folk say it's been making noises again."

She glances toward the dying hearth, then back at you, the question plain in her face. "You planning to go look for her tonight, love?"

## T37 | I ask the drover whether she remembers what I bought from her earlier.
time: 6.0 s | pre-dawn | Valley Inn | Brenna Holt | 2g 9s 7c | 0/3 | cloak, knife, Mug of Ale
GM: Brenna pauses in the act of banking the last coals, her eyes brightening with recognition. "The drover? You mean Mags Ferrow, the one with the salt cart that got itself torched in the yard three nights back? She left at first light yesterday, heading west again with what little she could salvage. I don't recall you buying anything off her, love. She was in a foul temper and mostly shouting about the Tinjacks, not trading." She straightens, wiping her hands on a rag that has seen better days, and gives you a thoughtful look. "If it's goods you're after, I've still got a few loaves left from yesterday, two copper each, or another mug of ale before I shut the taps. Otherwise the square opens at dawn; Mags usually circles back through there if the road doesn't swallow her again."

The inn feels emptier now, just the two of you and the dying glow of the hearth. Outside, the wind carries the faint clank of a harness from the yard where Tam is still seeing to the last mule.

## T38 | I wait by the hearth until evening.
time: 6.5 s | Day 2 · evening | Valley Inn | Brenna Holt | 2g 9s 7c | 0/3 | cloak, knife, Mug of Ale | final sheet Insight 15, Melee 15, Persuasion 25, Stealth 20
GM: You settle by the hearth as the last of the miners shuffle out into the gathering dusk, their boots scraping on the threshold. Brenna moves between the empty tables with a quiet efficiency, banking the fire low and sliding the heavy bolt across the front door. "Even the hills need sleep," she murmurs, voice softer now that the room has emptied. The stew pot has gone cold on its hook; the common room smells only of woodsmoke and the faint sourness of spilled ale left to dry.

Outside, the valley road lies quiet under early stars. Brenna glances your way once, curious but not pressing, then begins wiping down the scarred counter with a fresh rag. The night deepens, and the inn settles into its bones. A single lantern still burns above the bar, throwing long shadows across the floorboards.

She straightens, stretching her back with a small sigh. "If you're staying the night, love, it's three silver for the small room at the top of the stairs. Otherwise the common benches are yours for a copper. Either way, the fire's yours till morning." Her tone remains warm, but the hour is late and the work of closing is almost done.
