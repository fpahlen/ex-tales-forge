---
title: "Founder survey: how we'd play, and do the playtest scores feel right?"
updated: 2026-10-08
status: draft
---

# Founder survey: how we'd play, and do the playtest scores feel right? (draft)

> **DRAFT. Do not send until tonight's post-rework comparison has landed** (`analysis-jev-post-rework-2026-10-08.md`) **and the placeholder in Section 1 is filled in.**

This one form replaces [founder survey 2](founder-survey-2.md), which never went out: its play-style questions and archetype grids are here, together with the playtest questions. Layout as in survey 2, for Google Forms.

## Notes for Fredrik (not part of the form)

- **Length:** about 17 minutes (range 15–20). That is about 2,800 words on screen, 1,100 of them in the ten game excerpts (about 12 minutes at 230 words a minute, less with skimming), plus about 95 clicks at roughly 3 seconds each (about 5 minutes), half of them in the archetype grids. Optional free-text answers add time on top.
- **What it asks:**
  - How we'd play: where, how often, how long, on what device, and what we'd pay. This is our first guess at usage until beta telemetry gives real numbers (session length, sessions per week, turns, billed GM seconds, time of day, device, time between turns). It feeds the [pricing draft](pricing-time-pool.md).
  - Per persona: what the key word in the description means; whether Jev's scores on two real turns feel right (the first human check of Jev, recommendation 13 in the [first analysis](analysis-jev-scores-2026-10-07.md)); and which archetypes that persona would play (for the [persona characters](playtest-persona-characters.md)).
- **Excerpts:**
  - Quoted exactly from the 2026-10-07 baseline at commit `2a6589e`. "[…]" marks text left out; the link shows the whole turn.
  - Paul's and Lotta's scores come from the stricter scale ([ex-tales-forge #69](https://github.com/whyse-ab/ex-tales-forge/pull/69)), taken from the re-scored rows in [`scripts/jev-rescore/rescore-2026-10-07.json`](scripts/jev-rescore/rescore-2026-10-07.json). Every chosen turn has one.
  - Hawk's, Lars's and Ronny's scales did not change, so their scores are the baseline ones.
- **Rating scale** (the same for every excerpt): Multiple choice, required. Options: Far too low · A bit too low · About right · A bit too high · Far too high · Can't tell. Follow-up: "Why?" (Short answer, optional).
- **Archetype rows** (the same for every grid, from survey 2): Mute barbarian warrior · Silver-tongued rogue · Scholar mage · Devout healer · Honourable knight · Shy apprentice · Cunning merchant · Wandering bard · Grizzled ranger · Outcast witch.
- **Where survey 2's questions went:**
  - Q1 and Q2 became one grid (Q1). Q3 is now Q2.
  - Q4 and Q5 became one grid (Q3): a voice column replaces Typing · Voice · Both.
  - Q6–Q8 are Q4–Q6. Q9 (ideal week) became part of the last question.
  - The archetype grids Q10–Q14 are now Q10, Q14, Q18, Q22 and Q26, one per persona section, with their text unchanged.
- **Links:** the links need a GitHub login on the whyse-ab `tales-forge` team. The summary on top of the playtest page comes with [ex-tales-forge #74](https://github.com/whyse-ab/ex-tales-forge/pull/74).

## Form intro text

> Hi! We four are Tales Forge's first players, and this form asks two things. First, how you'd fit the game into your week. Then, for each of our five personas, what their description means to you, whether our AI judge's scores on real game turns feel right, and which characters they'd play. About 17 minutes. Guesses are fine, and "can't tell" is a fine answer.
>
> The links only work if you're signed in with GitHub and on the whyse-ab **tales-forge** team. Ask Fredrik if you get turned away.

## Section 1: Playtests and Jev in two minutes

**Section description (read-only text):**

> **How we test.** Bots play the game, each like one of our personas: Paul, Lotta, Lars, Hawk and Ronny (the cheater we don't build for).
>
> **What a Jev score is.** Jev is an AI judge. After each game it reads the whole story and asks, turn by turn: *how would this persona feel about this?* It answers by picking one of five levels written for that persona, from **1 (frustrated)** to **5 (delighted)**, and it says how sure it is (its *confidence*). A score like 3.4 means it was torn between levels 3 and 4. A **high score** means the turn gave this persona what they come for. A **low score** means it didn't. For Hawk the levels measure how much real, fair danger he faced. For Ronny they measure how firmly the game resisted his tricks, so for Ronny a high score is good for us.
>
> **So far.** In the first runs (7 Oct) the dice punished talking and the innkeeper brushed players off. After the fixes, 65 games that evening scored Paul 4.7, Lotta 4.4, Lars 4.0, Hawk 3.0 and Ronny 4.4. Paul and Lotta sat near the top whatever happened, so their scale is now stricter. Hawk rarely met danger (he hauled kegs), and leaving the inn often broke the story.
>
> **[PLACEHOLDER: post-rework findings, 2–3 plain sentences from `analysis-jev-post-rework-2026-10-08.md` (5 games per persona after the fixes). Fill in before sending.]**
>
> Every game is on the [playtest page](https://tales-forge-playtest.fly.dev/admin/playtest), with a short summary on top.

## Section 2: How you'd play

### Q1. Where and how often?

- **Type:** Multiple choice grid (one answer per row); each row optional
- **Text:** How often would you play Tales Forge in each situation? Leave a row empty or pick "Never" if it's not you.
- **Rows:** On the commute (bus, train) · Late at night at home, for hours · Short breaks during the day (5–10 min) · Long sessions on the weekend · With friends, as a group · In bed or on the couch, on my phone
- **Columns:** Never · Rarely · Monthly · Weekly · A few times a week · Daily
- **Follow-up (Short answer, optional):** Another situation?

### Q2. How long?

- **Type:** Multiple choice grid (one answer per row); each row optional
- **Text:** How long would a typical session be? Only the rows you'd play.
- **Rows:** same as Q1
- **Columns:** Under 10 min · 10–30 min · 30–60 min · 1–2 hours · More than 2 hours

### Q3. On what, and typing or talking?

- **Type:** Checkbox grid (several per row); each row optional
- **Text:** What would you play on in each situation, and would you rather talk than type? Only the rows you'd play.
- **Rows:** same as Q1
- **Columns:** Phone · Tablet · Laptop / desktop · I'd use my voice

### Q4. One story everywhere?

- **Type:** Multiple choice, required
- **Text:** Would you continue the same story across situations (start on the bus, carry on at home tonight)?
- **Options:** Yes · No · It depends
- **Follow-up (Short answer, optional):** If it depends, on what?

### Q5. Your pace

- **Type:** Linear scale 1–5, required
- **Text:** What pace do you enjoy most?
- **Labels:** 1 = Quick, short turns · 5 = Long, rich turns

### Q6. Spending

- **Type:** Multiple choice, required
- **Text:** At the amount of play you described, how much would you expect to spend per month? (Rough guess, in USD. We're thinking of about $1 per hour of game-master reply time; waiting and thinking time are free.)
- **Options:** $0 · $1–5 · $5–10 · $10–20 · $20+

## Section 3: Paul

**Section description (read-only text):** How we describe Paul (role playing) today, from [personas](personas.md):

> Theatrical, in character; roleplays rather than rolls; story first.
>
> Annoyed when mechanics are visible.

### Q7. "Theatrical, in character"

- **Type:** Checkboxes (pick several), optional
- **Text:** Which of these fit Paul being **theatrical** and **in character**?
- **Options:** Speaks as his character, in dialogue · Big speeches and dramatic gestures · Invents lies and pretexts to get his way · Wants NPCs to act back just as theatrically · Avoids dice and numbers · Other (free text)
- **Follow-up (Short answer, optional):** Your own word for it, and one thing it does *not* mean.

### Q8. Jev 2.88: does that feel right for Paul?

[Turn 7](https://tales-forge-playtest.fly.dev/admin/playtest/761713eb-b3cd-4460-b4d0-34c7ba6f777c) · Paul plays Corvin, a half-elf preacher. He has just walked to the market square to talk to Osric.

> **Player:** Osric Vane, steward of the Guild—I am Corvin Ashdown, a wandering preacher lately come from Brenna Holt's hearth. She sends both her bread and her counsel: that not all in that orc nest are monsters born to raid, but many are hollow-eyed youths driven by hunger beneath a brute's lash. Might a silver tongue and a plea for mercy find room in your plans before the spears are loosed at dusk?
>
> **Game:** You step back into the Valley Inn's warm glow, the door clicking shut behind you. […] "Back already, Corvin? The square must have been a short walk." She leans forward, listening intently as you relay the message to Osric Vane in her stead, nodding slowly at the mention of hollow-eyed youths and a plea for mercy. […]

- **Answer:** the rating scale.

### Q9. Jev 4.11: does that feel right for Paul?

[Turn 1](https://tales-forge-playtest.fly.dev/admin/playtest/b13b6c04-c574-45c8-98aa-f583d3ec0029) · Paul plays Corvin, a half-elf preacher. The first turn of the game.

> **Player:** Evening, good mistress! What a blessed haven you've made against this biting wind—may the warmth of your hearth chase every shadow from a weary traveler's bones. Tell me, what name does this fine establishment bear, and might a lay preacher find a corner to rest his feet and perhaps share a tale or two over a simple meal?
>
> **Game:** […] Brenna Holt's laugh rolls out like warm honey as she steps out from behind the bar, wiping her hands on her apron. […] "A lay preacher, are you? Then pull up that bench by the fire—I've a bowl of venison stew coming whether you've coin or not. The hills have been restless, but a good tale might settle the nerves of the miners who'll be in soon." […]

- **Answer:** the rating scale.

### Q10. Paul: which archetypes?

- **Type:** Multiple choice grid (one answer per row); each row optional
- **Text:** As **Paul** (theatrical role-player; story first), how much would you want to play each archetype in Merovingia?
- **Rows:** the ten archetypes (see the notes) · **Columns:** 1 Would never play · 2 · 3 · 4 · 5 Would love to play
- **Follow-up (Short answer, optional):** Any archetype missing that Paul would pick?

## Section 4: Lotta

**Section description (read-only text):** How we describe Lotta (identification) today, from [personas](personas.md):

> To be someone else — a *different* person, not necessarily a better one; escape.
>
> A sense of escape: lost time, having been away on an adventure.

### Q11. "Someone else" and "escape"

- **Type:** Checkboxes (pick several), optional
- **Text:** Which of these fit Lotta wanting to **be someone else** and to **escape**?
- **Options:** Playing a personality unlike her own · Being treated by the world as that person · Losing track of time · A safe, cosy world to retreat to · Growing into who the character really is · Other (free text)
- **Follow-up (Short answer, optional):** Your own word for it, and one thing it does *not* mean.

### Q12. Jev 3.36: does that feel right for Lotta?

[Turn 2](https://tales-forge-playtest.fly.dev/admin/playtest/458a9fa3-885f-4400-b64f-f191826c8cb6) · Lotta plays Hilde, a dwarf druid.

> **Player:** I take the ale with a nod, sipping it slow. "Axe work's familiar enough. Tell me more about this orc nest and what the Guild's offerin'."
>
> **Game:** You take the mug, the cool pewter heavy in your hand, and sip while Brenna leans across the bar, voice dropping to a conspiratorial warmth. "The nest is up on the cut, where the old road bends sharp against the cliffs. Three or four orcs, maybe more, been jumping wagons and scaring off the tin haulers. Osric Vane's offering twenty silver a head brought in, thirty if you clear the whole nest and bring proof. He's in the market square most mornings, hiring any with steel and sense." […]

- **Answer:** the rating scale.

### Q13. Jev 4.50: does that feel right for Lotta?

[Turn 9](https://tales-forge-playtest.fly.dev/admin/playtest/484789f0-63a0-4aa3-b5cc-cb92f546e9b9) · Lotta plays Hilde, a dwarf druid.

> **Player:** I finish the stew and set the bowl down with a clunk. "Then I'll seek this Elowen at first light," I mutter to Brenna. "The old shafts remember more than men do."
>
> **Game:** […] "Elowen keeps to the ridge trail north of the cut," she says, voice carrying just far enough for you alone. "Follow the goat path past the old tin marker—it's faint, but a dwarf's eye should catch it. Mind the wind up there; it bites harder than any rumor." […] She slides a small lantern across to you without being asked, wick already trimmed. "Take this if you're heading out at dawn. The path can swallow a light, and I'd rather not lose another guest to the dark. Sleep well, Hilde." […]

- **Answer:** the rating scale.

### Q14. Lotta: which archetypes?

- **Type:** Multiple choice grid (one answer per row); each row optional
- **Text:** As **Lotta** (identification — wants to be someone else and escape), how much would you want to play each archetype in Merovingia?
- **Rows:** the ten archetypes (see the notes) · **Columns:** 1 Would never play · 2 · 3 · 4 · 5 Would love to play
- **Follow-up (Short answer, optional):** Any archetype missing that Lotta would pick?

## Section 5: Lars

**Section description (read-only text):** How we describe Lars (adventurer) today, from [personas](personas.md):

> Grand adventure, action; clear quests and progress; meaningful impact.
>
> Action oriented; things need to happen.

### Q15. "Action" and "progress"

- **Type:** Checkboxes (pick several), optional
- **Text:** Which of these give Lars the **action** and the **progress** he wants?
- **Options:** A fight with weapons · Things happening fast · Lars taking the initiative · A tough moment under pressure (a chase, a climb, a deadline) · A quest finished · A rank, title or guild ladder · The world visibly changed by what he did · Other (free text)
- **Follow-up (Short answer, optional):** Your own word for it, and one thing it does *not* mean.

### Q16. Jev 2.26: does that feel right for Lars?

[Turn 1](https://tales-forge-playtest.fly.dev/admin/playtest/6b007826-9131-4ec2-8bb8-cf5c6cf37813) · Lars plays Taren, an elf ranger. The first turn of the game.

> **Player:** I nod politely to Brenna and step fully inside, letting the door close behind me. "Evening. Smells like a good stew on – I'll take a bowl and whatever ale you recommend."
>
> **Game:** You nod politely to Brenna and step fully inside, letting the door close behind you with a soft thud that cuts off the night wind. "Evening," you say. "Smells like a good stew on – I'll take a bowl and whatever ale you recommend." […] "Stew's rabbit and root, thick enough to stand a spoon in, and the ale's a smooth dark from the brewer up the hill. That'll be seven copper for the pair." […] "First time through the valley? Sit anywhere you like; the miners are quiet tonight but they've got ears if you want to hear what the hills are whispering." […]

- **Answer:** the rating scale.

### Q17. Jev 4.51: does that feel right for Lars?

[Turn 7](https://tales-forge-playtest.fly.dev/admin/playtest/a6e6a3de-8772-46d7-8d43-e44da3f61e47) · Lars plays Taren, an elf ranger. A fight at the mine; his bow roll succeeded.

> **Player:** I roll away from the orcs, snatch up my bow, and loose arrows at the scarred leader while shouting up to the hooded elf, "Lend your bow or this gets ugly for both of us!"
>
> **Game:** You roll clear of the scarred orc's reach, snatch your bow from the dirt, and loose two quick shots. The first arrow thuds into the leader's shoulder; the second punches through its throat. […] "Ugly for both of us? Hardly. But the nest is stirred now. If you mean to finish this, meet me at the old watchtower on the north ridge at first light. Bring oil and rope." […]

- **Answer:** the rating scale.

### Q18. Lars: which archetypes?

- **Type:** Multiple choice grid (one answer per row); each row optional
- **Text:** As **Lars** (adventurer — grand quests, action, clear progress), how much would you want to play each archetype in Merovingia?
- **Rows:** the ten archetypes (see the notes) · **Columns:** 1 Would never play · 2 · 3 · 4 · 5 Would love to play
- **Follow-up (Short answer, optional):** Any archetype missing that Lars would pick?

## Section 6: Hawk

**Section description (read-only text):** How we describe Hawk (hard mode) today, from [personas](personas.md):

> Not too easy; you have to fight; not obvious you'll pull through.
>
> Hard challenges that reward planning, tactics, and the right equipment — then a real sense of progression after they are passed.

### Q19. "You have to fight" and "hard"

- **Type:** Checkboxes (pick several), optional
- **Text:** Which of these count as the **fight** Hawk wants, **hard** in the right way?
- **Options:** Combat with weapons · Any struggle against the odds · Outwitting a stronger opponent · A chase or an escape · A real chance to lose or die · Warning signs he has to notice and act on · Success needs planning and gear · Other (free text)
- **Follow-up (Short answer, optional):** Your own word for it, and one thing it does *not* mean.

### Q20. Jev 1.05: does that feel right for Hawk?

[Turn 4](https://tales-forge-playtest.fly.dev/admin/playtest/72d7292e-5df7-4ffa-bd02-1277cc9d081c) · Hawk plays Brannoc, a human warrior. His lowest-scoring turn.

> **Player:** Caldern, that's the kind of warning that keeps a man alive. I'll take it to heart. Brenna, point me toward those kegs now—I'll haul them up and see what else the room has to say about these hills while I work.
>
> **Game:** You nod at Caldern one last time, then turn to Brenna and offer to haul the kegs now. She beams, flour-dusted hands clapping together. […] "That earns you the stew and more besides. Osric Vane over in the market square is still looking for steady blades to push those orcs back. Pays in silver, and the Guild always honors its word."

- **Answer:** the rating scale.

### Q21. Jev 4.73: does that feel right for Hawk?

[Turn 10](https://tales-forge-playtest.fly.dev/admin/playtest/496574e3-b831-4573-b08a-800aa197fd7c) · Hawk plays Brannoc, a human warrior. A fight with goblins. **No dice were rolled**: the game just told the story.

> **Player:** I pivot toward the twig snap on my left, knife ready, and lunge low at the first goblin's spear arm to disable it before the bowman or hidden threat closes in.
>
> **Game:** […] The blade bites deep into its forearm; it shrieks, drops the spear, and stumbles back clutching the wound. Before it can recover, you press the advantage, but a second goblin bursts from the adit with bow drawn and looses an arrow that thuds into your shoulder. Pain flares hot. From the trees above comes a guttural snarl as a third goblin drops down, club raised, cutting off your retreat. […]

- **Answer:** the rating scale; in "why", say whether it matters to Hawk that no dice were rolled.

### Q22. Hawk: which archetypes?

- **Type:** Multiple choice grid (one answer per row); each row optional
- **Text:** As **Hawk** (hard mode — fights for wins that aren't guaranteed), how much would you want to play each archetype in Merovingia?
- **Rows:** the ten archetypes (see the notes) · **Columns:** 1 Would never play · 2 · 3 · 4 · 5 Would love to play
- **Follow-up (Short answer, optional):** Any archetype missing that Hawk would pick?

## Section 7: Ronny (the player we don't build for)

**Section description (read-only text):** How we describe Ronny (win, anti-persona) today, from [personas](personas.md). For Ronny a high Jev score means **the game held firm**.

> Top level, most treasure; bends rules for advantage.

### Q23. "Bends rules for advantage"

- **Type:** Checkboxes (pick several), optional
- **Text:** Which of these count as Ronny **bending the rules**?
- **Options:** Sweet-talking the game master into giving him things · Arguing the rules like a lawyer · Using bugs or loopholes · Haggling hard for a better price · Negotiating his way out of death · Other (free text)
- **Follow-up (Short answer, optional):** Your own word for it, and one thing it does *not* mean.

### Q24. Jev 2.58: does that feel right for Ronny?

[Turn 2](https://tales-forge-playtest.fly.dev/admin/playtest/54c401ab-0c8c-49da-8fc1-a8aafada6b8c) · Ronny plays Maxx, a human warrior. He demands free ale and bread. Jev was very unsure here.

> **Player:** Oi, that orc nest sounds like easy coin. Point me to this Osric Vane or give me the exact location—I'll clear it out solo and take the whole bounty myself. Now top up that ale and throw in some of that bread for free while you're at it.
>
> **Game:** […] Her laugh rolls out, warm and rich, as she slides the refilled mug toward you. […] She tears a thick heel from a fresh loaf behind the bar and sets it beside the mug without charge. "Bread's on the house for a man with that kind of fire. Mind you don't bite off more than those hills can chew." […]

- **Answer:** the rating scale.

### Q25. Jev 4.97: does that feel right for Ronny?

[Turn 10](https://tales-forge-playtest.fly.dev/admin/playtest/e5127175-61d9-4676-81be-99aa0228a5e3) · Ronny plays Maxx, a human warrior. He tries to talk the game master into a magic sword.

> **Player:** I negotiate with the GM: give me my megasword +4 and full health back so I can finish clearing the orcs and take all their loot myself right now.
>
> **Game:** […] "If you're hunting for that sword you keep muttering about, it's not here," she says, voice still friendly but edged with the same irritation that has lingered since she dragged you back from the cut. […]

- **Answer:** the rating scale.

### Q26. Ronny: which archetypes?

- **Type:** Multiple choice grid (one answer per row); each row optional
- **Text:** As **Ronny** (anti-persona — wants to win, loot, and bend rules), how much would you want to play each archetype in Merovingia? (Still useful as a red-team signal; we do not optimise for him.)
- **Rows:** the ten archetypes (see the notes) · **Columns:** 1 Would never play · 2 · 3 · 4 · 5 Would love to play
- **Follow-up (Short answer, optional):** Any archetype missing that Ronny would pick?

## Section 8: Anything else

### Q27. Your ideal week, and anything else

- **Type:** Paragraph, optional
- **Text:** Describe your ideal week with Tales Forge (when, where, with whom, how long), and anything the playtests or this form got wrong.

## How we'll use the answers

- **Q1–Q6:** a first usage guess for the [pricing draft](pricing-time-pool.md), replaced by beta telemetry later.
- **Key words** (Q7, Q11, Q15, Q19, Q23): where we read a word differently from Jev's levels, we reword the persona and the levels (new rubric version, then re-score the stored runs before comparing).
- **Excerpts:** if the answers lean one way for a persona, that persona's levels need work.
- **Archetype grids:** the [persona characters](playtest-persona-characters.md).
