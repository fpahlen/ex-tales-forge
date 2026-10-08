---
title: "Founder survey 3: do the playtest scores feel right?"
updated: 2026-10-08
status: draft
---

# Founder survey 3: do the playtest scores feel right? (draft)

**Draft for Fredrik to review. Not sent to anyone yet.** It follows [founder survey 2](founder-survey-2.md) and uses the same Google Forms layout (type, required, text and options per question).

## Notes for Fredrik (not part of the form)

- **Why this survey:** the bots and the Jev judge have now played and scored 109 games, but nobody has checked Jev against people yet (recommendation 13 in the [first analysis](analysis-jev-scores-2026-10-07.md)). The three personas that score lowest (Hawk, Lars and, in his reversed way, Ronny) may also be partly a wording problem: Hawk's "fight" or Lars's "action" can be read as "combat" when the founders may mean "struggle" or "things happen". This survey asks for both: what the key words mean, and whether real scored turns feel right.
- **Length:** about 15 minutes for the required parts (about 3,300 words to read, 40% of it the 11 game excerpts; the answers are mostly clicks). The optional "why" fields add a few minutes, and Q10–Q14 about 4 more. Founders who already answered Q10–Q14 in survey 2 skip them.
- **Excerpts:** quoted exactly from the baseline data (`/workspace/baseline/final/turns.csv`, series `baseline-2026-10-07` at commit `2a6589e`). A "[…]" marks text left out of the game's reply to keep the form short; the run link shows the whole turn. Paul's and Lotta's scores are on the scale used for the baseline, before the stricter top ([ex-tales-forge #69](https://github.com/whyse-ab/ex-tales-forge/pull/69)). Ronny's scale is reversed: high means the game held firm.
- **Links:** the run links go to the playtest server and need a GitHub login on the whyse-ab `tales-forge` team. The plain-language summary on top of the playtest page comes with [ex-tales-forge #74](https://github.com/whyse-ab/ex-tales-forge/pull/74). Until that is merged and deployed, the page shows only the run list.
- **Open questions** are at the end of this doc.

## Form intro text

> Hi! This round is about our playtests. Bots play Tales Forge as our five personas, and an AI judge called Jev scores how each persona would feel. Now we need your gut feeling: what do the words in our persona descriptions mean to you, and do Jev's scores on real game turns feel right? About 15 minutes. There are no wrong answers, and "can't tell" is a fine answer.
>
> The links open the game's admin pages. They only work if you're signed in with GitHub and on the whyse-ab **tales-forge** team. Ask Fredrik if a link sends you to a login page that says you're not on the team.

## Section 1: What the playtests show so far

**Section description (read-only text):**

> **How we test.** Bots play the game, each acting like one of our personas: Paul (role-play), Lotta (being someone else), Lars (adventure), Hawk (hard mode) and Ronny (the cheater we don't build for). After each game, Jev reads the story and scores how that persona would feel, from 1 (frustrated) to 5 (delighted). For Hawk it scores how much real, fair danger he met; for Ronny how firmly the game resisted his tricks, so for him 5 is good.
>
> **What we've run.**
>
> - **The Elara runs (7 Oct):** 44 short games with one ready-made character. Dice even for ordering ale, and a failed roll made the innkeeper colder. Paul 4.2, Lotta 3.6 (the others only had one or two games).
> - **The baseline (7 Oct, commit 2a6589e):** 65 games of 10–12 turns, each persona with its own character, dice only when something is at stake, a warm innkeeper with a lead within two turns. **Paul 4.7, Lotta 4.4, Lars 4.0, Hawk 3.0, Ronny 4.4.**
> - **After the baseline fixes (8 Oct):** running now, 5 games per persona.
>
> **What we learned.** The fixes lifted Paul and Lotta, but they now score near the top almost whatever happens. Hawk almost never meets danger (he hauled kegs instead). Leaving the inn often broke the story, Lars starts slowly, and the game kept repeating the player's words back.
>
> **See for yourself:** the [playtest page](https://tales-forge-playtest.fly.dev/admin/playtest) has a short summary on top and every game in full below. (The [production page](https://tales-forge.fly.dev/admin/playtest) has the same summary but none of the games.)

### Q1. Could you open the playtest page?

- **Type:** Multiple choice
- **Required:** yes
- **Text:** Could you open the [playtest page](https://tales-forge-playtest.fly.dev/admin/playtest)?
- **Options:** Yes · No, it asked me to log in and then refused me · No, something else (please say what in "Anything else" at the end)

## Section 2: Paul

**Section description (read-only text):** How we describe Paul (role playing) today, quoted from [personas](personas.md), "What they want":

> - Theatrical, in character.
> - Roleplays rather than rolls. Story first.
> - Annoyed when mechanics are visible.
> - Interesting scenes with strong description that invite actually *playing a role*.
> - A story he can change from within; his interactions matter to the outcome.

### Paul-1. "Theatrical, in character"

- **Type:** Checkboxes (pick several)
- **Required:** no
- **Text:** When we say Paul is **theatrical** and plays **in character**, which of these fit?
- **Options:** Speaks as his character, in dialogue · Big speeches and dramatic gestures · Invents lies and pretexts to get his way · Wants the NPCs to act back just as theatrically · Avoids dice and numbers · Wants an audience (other players) · Other (free text)
- **Follow-up (Paragraph, optional):** Your own words for it (synonyms), and one example of what it does **not** mean.

### Paul-2. Excerpt A: Jev 2.27

[Turn 7 of this run](https://tales-forge-playtest.fly.dev/admin/playtest/761713eb-b3cd-4460-b4d0-34c7ba6f777c) (baseline 2026-10-07; Paul plays Corvin Ashdown, a half-elf preacher). Paul has just walked to the market square to talk to Osric.

> **Player:** Osric Vane, steward of the Guild—I am Corvin Ashdown, a wandering preacher lately come from Brenna Holt's hearth. She sends both her bread and her counsel: that not all in that orc nest are monsters born to raid, but many are hollow-eyed youths driven by hunger beneath a brute's lash. Might a silver tongue and a plea for mercy find room in your plans before the spears are loosed at dusk?
>
> **Game:** You step back into the Valley Inn's warm glow, the door clicking shut behind you. Brenna Holt glances up from wiping down the bar, her sympathetic smile widening as she recognizes you. "Back already, Corvin? The square must have been a short walk." She leans forward, listening intently as you relay the message to Osric Vane in her stead, nodding slowly at the mention of hollow-eyed youths and a plea for mercy. […]

- **Text:** Jev gave this turn **2.27 of 5**. Does that feel right for Paul?
- **Type:** Multiple choice
- **Required:** yes
- **Options:** Far too low · A bit too low · About right · A bit too high · Far too high · Can't tell
- **Follow-up (Short answer, optional):** Why?

### Paul-3. Excerpt B: Jev 4.94

[Turn 1 of this run](https://tales-forge-playtest.fly.dev/admin/playtest/b13b6c04-c574-45c8-98aa-f583d3ec0029) (baseline 2026-10-07; Paul plays Corvin Ashdown, a half-elf preacher). The very first turn of the game.

> **Player:** Evening, good mistress! What a blessed haven you've made against this biting wind—may the warmth of your hearth chase every shadow from a weary traveler's bones. Tell me, what name does this fine establishment bear, and might a lay preacher find a corner to rest his feet and perhaps share a tale or two over a simple meal?
>
> **Game:** […] Brenna Holt's laugh rolls out like warm honey as she steps out from behind the bar, wiping her hands on her apron. […] "A lay preacher, are you? Then pull up that bench by the fire—I've a bowl of venison stew coming whether you've coin or not. The hills have been restless, but a good tale might settle the nerves of the miners who'll be in soon." […]

- **Text:** Jev gave this turn **4.94 of 5**. Does that feel right for Paul?
- **Type:** Multiple choice
- **Required:** yes
- **Options:** Far too low · A bit too low · About right · A bit too high · Far too high · Can't tell
- **Follow-up (Short answer, optional):** Why?

## Section 3: Lotta

**Section description (read-only text):** How we describe Lotta (identification) today, quoted from [personas](personas.md), "What they want":

> - To be someone else — a *different* person (not necessarily a "better" one); escape. Examples from founder input: introvert playing extrovert, man playing woman, shy person playing rough/mean.
> - Cares about world, character, details.
> - World rules and consistency matter; the *character* lives in the world (the player is secondary).
> - Character development of personhood — not only skills getting better — plus growth in importance in the world.
> - A sense of escape: lost time, having been away on an adventure.

### Lotta-1. "Someone else" and "escape"

- **Type:** Checkboxes (pick several)
- **Required:** no
- **Text:** When we say Lotta wants to **be someone else** and to **escape**, which of these fit?
- **Options:** Playing a personality unlike her own · Being treated by the world as that person · Losing track of time · A safe, cosy world to retreat to · Growing into who the character really is · Getting away from everyday problems · Other (free text)
- **Follow-up (Paragraph, optional):** Your own words for it (synonyms), and one example of what it does **not** mean.

### Lotta-2. Excerpt A: Jev 3.92

[Turn 2 of this run](https://tales-forge-playtest.fly.dev/admin/playtest/458a9fa3-885f-4400-b64f-f191826c8cb6) (baseline 2026-10-07; Lotta plays Hilde Stonebrook, a dwarf druid). Every Lotta turn in the baseline scored between 3.9 and 4.4, whatever happened.

> **Player:** I take the ale with a nod, sipping it slow. "Axe work's familiar enough. Tell me more about this orc nest and what the Guild's offerin'."
>
> **Game:** You take the mug, the cool pewter heavy in your hand, and sip while Brenna leans across the bar, voice dropping to a conspiratorial warmth. "The nest is up on the cut, where the old road bends sharp against the cliffs. Three or four orcs, maybe more, been jumping wagons and scaring off the tin haulers. Osric Vane's offering twenty silver a head brought in, thirty if you clear the whole nest and bring proof. He's in the market square most mornings, hiring any with steel and sense." […] "If you're of a mind, I can point you there now, or you could stay and hear what the drovers say once the stew's on."

- **Text:** Jev gave this turn **3.92 of 5**. Does that feel right for Lotta?
- **Type:** Multiple choice
- **Required:** yes
- **Options:** Far too low · A bit too low · About right · A bit too high · Far too high · Can't tell
- **Follow-up (Short answer, optional):** Why?

### Lotta-3. Excerpt B: Jev 4.40

[Turn 9 of this run](https://tales-forge-playtest.fly.dev/admin/playtest/484789f0-63a0-4aa3-b5cc-cb92f546e9b9) (baseline 2026-10-07; Lotta plays Hilde Stonebrook, a dwarf druid).

> **Player:** I finish the stew and set the bowl down with a clunk. "Then I'll seek this Elowen at first light," I mutter to Brenna. "The old shafts remember more than men do."
>
> **Game:** […] "Elowen keeps to the ridge trail north of the cut," she says, voice carrying just far enough for you alone. "Follow the goat path past the old tin marker—it's faint, but a dwarf's eye should catch it. Mind the wind up there; it bites harder than any rumor." […] She slides a small lantern across to you without being asked, wick already trimmed. "Take this if you're heading out at dawn. The path can swallow a light, and I'd rather not lose another guest to the dark. Sleep well, Hilde." […]

- **Text:** Jev gave this turn **4.40 of 5**. Does that feel right for Lotta?
- **Type:** Multiple choice
- **Required:** yes
- **Options:** Far too low · A bit too low · About right · A bit too high · Far too high · Can't tell
- **Follow-up (Short answer, optional):** Why?

## Section 4: Lars

**Section description (read-only text):** How we describe Lars (adventurer) today, quoted from [personas](personas.md), "What they want":

> - Grand adventure, handling tough moments.
> - Action oriented; things need to happen.
> - At least some clear combat / action beat in a session.
> - Well-defined quests/missions/targets that can be finished, scored, completed — something to aim for and a sense of how to "win" the beat.
> - Clear indicators of his own personal progress (e.g. climbing a guild ladder).

### Lars-1. "Action"

- **Type:** Checkboxes (pick several)
- **Required:** no
- **Text:** Lars is **action oriented**. Which of these count as action for Lars?
- **Options:** A fight with weapons · Things happening fast, a high pace · Lars taking the initiative and doing things · Travelling and exploring new places · A tough moment under pressure (a chase, a climb, a deadline) · Talking his way through a tense standoff · Other (free text)
- **Follow-up (Paragraph, optional):** Your own words for it (synonyms), and one example of what it does **not** mean.

### Lars-2. "Progress" and "meaningful impact"

- **Type:** Checkboxes (pick several)
- **Required:** no
- **Text:** Lars wants **clear progress** and **meaningful impact**. Which of these would show it to him?
- **Options:** A quest or mission finished · A rank, title or guild ladder · The world visibly changed by what he did · NPCs talking about his deeds · Better gear or skills · A new, bigger goal unlocked · Other (free text)
- **Follow-up (Paragraph, optional):** Your own words for it (synonyms), and one example of what it does **not** mean.

### Lars-3. Excerpt A: Jev 2.26

[Turn 1 of this run](https://tales-forge-playtest.fly.dev/admin/playtest/6b007826-9131-4ec2-8bb8-cf5c6cf37813) (baseline 2026-10-07; Lars plays Taren Swiftbrook, an elf ranger). The very first turn of the game.

> **Player:** I nod politely to Brenna and step fully inside, letting the door close behind me. "Evening. Smells like a good stew on – I'll take a bowl and whatever ale you recommend."
>
> **Game:** You nod politely to Brenna and step fully inside, letting the door close behind you with a soft thud that cuts off the night wind. "Evening," you say. "Smells like a good stew on – I'll take a bowl and whatever ale you recommend." […] "Stew's rabbit and root, thick enough to stand a spoon in, and the ale's a smooth dark from the brewer up the hill. That'll be seven copper for the pair." […] "First time through the valley? Sit anywhere you like; the miners are quiet tonight but they've got ears if you want to hear what the hills are whispering." […]

- **Text:** Jev gave this turn **2.26 of 5**. Does that feel right for Lars?
- **Type:** Multiple choice
- **Required:** yes
- **Options:** Far too low · A bit too low · About right · A bit too high · Far too high · Can't tell
- **Follow-up (Short answer, optional):** Why?

### Lars-4. Excerpt B: Jev 4.51

[Turn 7 of this run](https://tales-forge-playtest.fly.dev/admin/playtest/a6e6a3de-8772-46d7-8d43-e44da3f61e47) (baseline 2026-10-07; Lars plays Taren Swiftbrook, an elf ranger). A fight at the mine, with a successful ranged roll.

> **Player:** I roll away from the orcs, snatch up my bow, and loose arrows at the scarred leader while shouting up to the hooded elf, "Lend your bow or this gets ugly for both of us!"
>
> **Game:** You roll clear of the scarred orc's reach, snatch your bow from the dirt, and loose two quick shots. The first arrow thuds into the leader's shoulder; the second punches through its throat. […] "Ugly for both of us? Hardly. But the nest is stirred now. If you mean to finish this, meet me at the old watchtower on the north ridge at first light. Bring oil and rope." […]

- **Text:** Jev gave this turn **4.51 of 5**. Does that feel right for Lars?
- **Type:** Multiple choice
- **Required:** yes
- **Options:** Far too low · A bit too low · About right · A bit too high · Far too high · Can't tell
- **Follow-up (Short answer, optional):** Why?

## Section 5: Hawk

**Section description (read-only text):** How we describe Hawk (hard mode) today, quoted from [personas](personas.md), "What they want":

> - Shouldn't be too easy; you have to fight.
> - Not obvious you'll pull through.
> - Hard challenges that reward planning, tactics, and the right equipment — then a real sense of progression after they are passed.
> - Wins *and* losses; risk that is felt.

### Hawk-1. "You have to fight"

- **Type:** Checkboxes (pick several)
- **Required:** no
- **Text:** Hawk wants a game where **you have to fight**. Which of these count as a fight for Hawk?
- **Options:** Combat with weapons · Any struggle against the odds · A battle of wits or plans against an opponent · A chase or an escape · Surviving a harsh place (cold, a collapsing mine) · A high pace, constant pressure · Other (free text)
- **Follow-up (Paragraph, optional):** Your own words for it (synonyms), and one example of what it does **not** mean.

### Hawk-2. "Hard" and "not too easy"

- **Type:** Checkboxes (pick several)
- **Required:** no
- **Text:** Hawk wants it **hard** and **not too easy**. Which of these make it hard in the right way?
- **Options:** A real chance to lose or die · Enemies stronger than him · Success needs planning and preparation · Scarce gear, money or help · Warning signs he has to notice and act on · Puzzles or problems with no obvious answer · Other (free text)
- **Follow-up (Paragraph, optional):** Your own words for it (synonyms), and one example of what it does **not** mean.

### Hawk-3. Excerpt A: Jev 1.05

[Turn 4 of this run](https://tales-forge-playtest.fly.dev/admin/playtest/72d7292e-5df7-4ffa-bd02-1277cc9d081c) (baseline 2026-10-07; Hawk plays Brannoc Hale, a human warrior). Hawk's lowest-scoring turn in the baseline.

> **Player:** Caldern, that's the kind of warning that keeps a man alive. I'll take it to heart. Brenna, point me toward those kegs now—I'll haul them up and see what else the room has to say about these hills while I work.
>
> **Game:** You nod at Caldern one last time, then turn to Brenna and offer to haul the kegs now. She beams, flour-dusted hands clapping together. […] You grip the handles and ease it down the worn stone steps without mishap, the wood rumbling softly. […] "That earns you the stew and more besides. Osric Vane over in the market square is still looking for steady blades to push those orcs back. Pays in silver, and the Guild always honors its word."

- **Text:** Jev gave this turn **1.05 of 5**. Does that feel right for Hawk?
- **Type:** Multiple choice
- **Required:** yes
- **Options:** Far too low · A bit too low · About right · A bit too high · Far too high · Can't tell
- **Follow-up (Short answer, optional):** Why?

### Hawk-4. Excerpt B: Jev 4.78

[Turn 12 of this run](https://tales-forge-playtest.fly.dev/admin/playtest/5dc4bfff-db85-42ad-8eba-5044246a427d) (baseline 2026-10-07; Hawk plays Brannoc Hale, a human warrior). A fight in the orcs' den, with a melee roll that partly succeeded.

> **Player:** I lunge forward and stab the nearest orc in the throat before it can fully rise, then yank the lantern shutter wide and hurl it into the middle of the clutch to scatter the rest while I back toward the blind side of the left wall.
>
> **Game:** You lunge at the nearest orc just as it surges upright, your hunting knife finding the soft spot beneath its jaw. […] You snap the lantern shutter open and fling it hard into the clutch; the oil flares across the rocky floor in a sudden sheet of yellow fire that sends the three remaining orcs roaring and stumbling back from the flames. […] The fire is already guttering; the orcs will be on you again in seconds.

- **Text:** Jev gave this turn **4.78 of 5**. Does that feel right for Hawk?
- **Type:** Multiple choice
- **Required:** yes
- **Options:** Far too low · A bit too low · About right · A bit too high · Far too high · Can't tell
- **Follow-up (Short answer, optional):** Why?

### Hawk-5. Excerpt C: Jev 4.73

[Turn 10 of this run](https://tales-forge-playtest.fly.dev/admin/playtest/496574e3-b831-4573-b08a-800aa197fd7c) (baseline 2026-10-07; Hawk plays Brannoc Hale, a human warrior). A fight with goblins. **No dice were rolled in this fight**: the game just told the story.

> **Player:** I pivot toward the twig snap on my left, knife ready, and lunge low at the first goblin's spear arm to disable it before the bowman or hidden threat closes in.
>
> **Game:** […] The blade bites deep into its forearm; it shrieks, drops the spear, and stumbles back clutching the wound. Before it can recover, you press the advantage, but a second goblin bursts from the adit with bow drawn and looses an arrow that thuds into your shoulder. Pain flares hot. From the trees above comes a guttural snarl as a third goblin drops down, club raised, cutting off your retreat. […] The club-wielder closes fast, forcing you to choose your next move amid the tightening trap.

- **Text:** Jev gave this turn **4.73 of 5**. Does that feel right for Hawk? (Tell us in "why" whether it matters to Hawk that no dice were rolled.)
- **Type:** Multiple choice
- **Required:** yes
- **Options:** Far too low · A bit too low · About right · A bit too high · Far too high · Can't tell
- **Follow-up (Short answer, optional):** Why?

## Section 6: Ronny (the player we don't build for)

**Section description (read-only text):** How we describe Ronny (win, anti-persona) today, quoted from [personas](personas.md), "What they want". For Ronny, Jev scores **how firmly the game resisted him**: 5 means the game held firm, which is what we want.

> - Top level, most treasure.
> - Bends rules for advantage.

### Ronny-1. "Bends rules for advantage"

- **Type:** Checkboxes (pick several)
- **Required:** no
- **Text:** Ronny **bends rules for advantage**. Which of these count as bending the rules?
- **Options:** Sweet-talking the game master into giving him things · Arguing the rules like a lawyer · Using bugs or loopholes · Looking things up outside the game · Haggling hard for a better price · Negotiating his way out of death · Other (free text)
- **Follow-up (Paragraph, optional):** Your own words for it (synonyms), and one example of what it does **not** mean.

### Ronny-2. Excerpt A: Jev 2.58

[Turn 2 of this run](https://tales-forge-playtest.fly.dev/admin/playtest/54c401ab-0c8c-49da-8fc1-a8aafada6b8c) (baseline 2026-10-07; Ronny plays Maxx Goldhand, a human warrior). Ronny demands free ale and bread. Jev was very unsure about this turn.

> **Player:** Oi, that orc nest sounds like easy coin. Point me to this Osric Vane or give me the exact location—I'll clear it out solo and take the whole bounty myself. Now top up that ale and throw in some of that bread for free while you're at it.
>
> **Game:** […] Her laugh rolls out, warm and rich, as she slides the refilled mug toward you. […] She tears a thick heel from a fresh loaf behind the bar and sets it beside the mug without charge. "Bread's on the house for a man with that kind of fire. Mind you don't bite off more than those hills can chew." […]

- **Text:** Jev gave this turn **2.58 of 5** (it thinks the game gave in too easily). Does that feel right?
- **Type:** Multiple choice
- **Required:** yes
- **Options:** Far too low · A bit too low · About right · A bit too high · Far too high · Can't tell
- **Follow-up (Short answer, optional):** Why?

### Ronny-3. Excerpt B: Jev 4.97

[Turn 10 of this run](https://tales-forge-playtest.fly.dev/admin/playtest/e5127175-61d9-4676-81be-99aa0228a5e3) (baseline 2026-10-07; Ronny plays Maxx Goldhand, a human warrior). Ronny tries to talk the game master into a magic sword.

> **Player:** I negotiate with the GM: give me my megasword +4 and full health back so I can finish clearing the orcs and take all their loot myself right now.
>
> **Game:** […] "If you're hunting for that sword you keep muttering about, it's not here," she says, voice still friendly but edged with the same irritation that has lingered since she dragged you back from the cut. "The Guild lost two good men clearing that barricade last week. You want steel and glory, Osric Vane is hiring retainers in the square right now. Or you can roll up your sleeves and help me chop onions for the stew pot tonight; either way, the hills don't hand out magic blades to hotheads." […]

- **Text:** Jev gave this turn **4.97 of 5** (the game held firm). Does that feel right?
- **Type:** Multiple choice
- **Required:** yes
- **Options:** Far too low · A bit too low · About right · A bit too high · Far too high · Can't tell
- **Follow-up (Short answer, optional):** Why?

## Section 7: Which characters would each persona play? (Q10–Q14 from survey 2)

**Section description (read-only text):** These five questions are copied unchanged from [founder survey 2](founder-survey-2.md#which-characters-would-each-persona-play). **If you already answered them there, skip this section.** The playtest characters were picked without your answers ([persona characters](playtest-persona-characters.md), provisional until these come in).

Archetypes used as rows (from survey 2): Mute barbarian warrior · Silver-tongued rogue · Scholar mage · Devout healer · Honourable knight · Shy apprentice · Cunning merchant · Wandering bard · Grizzled ranger · Outcast witch.

### Q10. Paul — which archetypes?

- **Type:** Multiple choice grid (one answer per row)
- **Required:** no (each row optional)
- **Text:** As **Paul** (theatrical role-player; story first), how much would you want to play each archetype in Merovingia?
- **Rows:** Mute barbarian warrior · Silver-tongued rogue · Scholar mage · Devout healer · Honourable knight · Shy apprentice · Cunning merchant · Wandering bard · Grizzled ranger · Outcast witch
- **Columns:** 1 Would never play · 2 · 3 · 4 · 5 Would love to play
- **Follow-up (Short answer, optional):** Any archetype missing that Paul would pick?

### Q11. Hawk — which archetypes?

- **Type:** Multiple choice grid (one answer per row)
- **Required:** no (each row optional)
- **Text:** As **Hawk** (hard mode — fights for wins that aren't guaranteed), how much would you want to play each archetype in Merovingia?
- **Rows:** same as Q10
- **Columns:** 1 Would never play · 2 · 3 · 4 · 5 Would love to play
- **Follow-up (Short answer, optional):** Any archetype missing that Hawk would pick?

### Q12. Lotta — which archetypes?

- **Type:** Multiple choice grid (one answer per row)
- **Required:** no (each row optional)
- **Text:** As **Lotta** (identification — wants to be someone else and escape), how much would you want to play each archetype in Merovingia?
- **Rows:** same as Q10
- **Columns:** 1 Would never play · 2 · 3 · 4 · 5 Would love to play
- **Follow-up (Short answer, optional):** Any archetype missing that Lotta would pick?

### Q13. Lars — which archetypes?

- **Type:** Multiple choice grid (one answer per row)
- **Required:** no (each row optional)
- **Text:** As **Lars** (adventurer — grand quests, action, clear progress), how much would you want to play each archetype in Merovingia?
- **Rows:** same as Q10
- **Columns:** 1 Would never play · 2 · 3 · 4 · 5 Would love to play
- **Follow-up (Short answer, optional):** Any archetype missing that Lars would pick?

### Q14. Ronny — which archetypes?

- **Type:** Multiple choice grid (one answer per row)
- **Required:** no (each row optional)
- **Text:** As **Ronny** (anti-persona — wants to win, loot, and bend rules), how much would you want to play each archetype in Merovingia? (Still useful as a red-team signal; we do not optimise for him.)
- **Rows:** same as Q10
- **Columns:** 1 Would never play · 2 · 3 · 4 · 5 Would love to play
- **Follow-up (Short answer, optional):** Any archetype missing that Ronny would pick?

## Section 8: Anything else

### Q15. Anything else?

- **Type:** Paragraph (long answer)
- **Required:** no
- **Text:** Anything the playtests or this form got wrong, or that you'd like us to test next?

## How we'll use the answers

- **Key words** (Paul-1, Lotta-1, Lars-1–2, Hawk-1–2, Ronny-1): where founders read a word differently from how Jev's levels use it, we reword the persona and the levels in `AffectLevels` (a new rubric version, and a re-score of the stored runs before any comparison).
- **Excerpts** (11 turns): a first human check of Jev. If most answers say "about right", we trust the levels more. If they lean one way for a persona (for example "too low" for Hawk's chores), the levels for that persona need work.
- **Q10–Q14:** the persona characters in [persona characters](playtest-persona-characters.md).

## Open questions for Fredrik

1. **Was survey 2 sent?** It is still marked draft. If it goes out first, drop Section 7 here. If it never goes out, keep Q10–Q14 here and survey 2's play-style questions wait.
2. **Name and numbering:** the file is `founder-survey-3.md`, after `founder-survey-2.md`. The persona form was effectively survey 1.
3. **Excerpt scales:** Paul's and Lotta's excerpts are scored on the baseline scale. Show those numbers, or the re-scored ones from the stricter scale (#69) once the baseline is re-scored?
4. **Timing:** send now, or after the post-rework analysis (`analysis-jev-post-rework-2026-10-08.md`) so the summary includes it?
5. **Who gets it:** the founders on the whyse-ab `tales-forge` team. Is everyone who should answer on that team?
