# Tales Forge: forum persona research
Date: 2026-10-15 (Europe/Stockholm). Method: public pages only, read with WebSearch and WebFetch (plus curl HEAD-style status checks). I did not post, sign up or log in anywhere. I left usernames out and paraphrased; the few short quotes are anonymous.

**How each source was read.** **[F]** means I opened the page in full with WebFetch. **[S]** means I read the thread text through the search index's page excerpts, because direct fetches of reddit.com (and Giant in the Playground) timed out or got a 403 from this box. Every [S] URL below came back with real excerpts from that thread. None of them are guesses. Even so, a full manual read of the [S] threads before acting on any single quote would be worth doing.

---
## 1. Existing personas (source: `whyse-ab/ex-tales-forge/priv/playtest/personas.md`, updated 2026-10-07; also PRODUCT.md "User personas"; `tales-forge-docs/decisions/d-002-persona-scorecards.md` (scorecards, still open))
Core audience as written: **Gen-X first-generation RPG players.** There are four target personas and one anti-persona.
- **Hawk (hard mode):** wants a challenge that is hard but fair and foreshadowed, with tactics, gear and progression. On death: "shit happens." Quits if the game is too easy, or if it kills him unfairly.
- **Paul (role player):** plays in character, story first, and doesn't want mechanics on screen (dice hidden by a setting). The GM has to infer intent from dialogue, and a good bluff should matter more than a bad roll.
- **Lotta (identification):** wants to be a *different* person and escape. She cares about world consistency, an "ugly duckling" arc, and NPCs reacting to who she is. Death devastates her and is a quit risk ("dead but not gone", character museum).
- **Lars (adventurer):** wants action, at least one fight per session, quests he can finish, visible progress (a guild ladder) and impact on the world.
- **Ronny (anti-persona, "win"):** wants max level and loot, and bends rules, sweet-talks or prompt-injects the GM, and games the economy. He is the red-team target, and the game should resist him in-fiction.
The docs currently say there is **no missing persona yet**.

---
## 2. Forums and communities (status checked 2026-10-15)
| # | Community | URL | Good for | Public? / live |
|---|---|---|---|---|
| 1 | Roll20 Community Forums | https://app.roll20.net/forum/ | Online VTT players, play-by-post (PbP) and text-game feature requests | Public read, 200 |
| 2 | DDO official forums | https://forums.ddo.com/ (game: https://www.ddo.com/home) | Long-term online D&D players: difficulty, solo vs group, retention | Public read, 200 |
| 3 | r/ddo | https://www.reddit.com/r/ddo/ | Why DDO players stay or leave | Public, 200 (old.reddit) |
| 4 | r/rpg | https://www.reddit.com/r/rpg/ | Broad TTRPG; AI GM debate; session length | Public, 200 |
| 5 | r/DnD | https://www.reddit.com/r/DnD/ | Mainstream D&D players, GM expectations, character death | Public, 200 |
| 6 | r/Solo_Roleplaying | https://www.reddit.com/r/Solo_Roleplaying/ | Closest to TF's user: solo play with an AI GM | Public, 200 |
| 7 | r/AIDungeon | https://www.reddit.com/r/AIDungeon/ | Paying AI-adventure users: memory, stakes, subscriptions | Public, 200 |
| 8 | r/NovelAi | https://www.reddit.com/r/NovelAi/ | AI text-adventure and storyteller mode users | Public, 200 |
| 9 | r/SillyTavernAI | https://www.reddit.com/r/SillyTavernAI/ | Power users building their own AI GM/RP setups | Public, 200 |
| 10 | r/ai_game_master | https://www.reddit.com/r/ai_game_master/ | Reviews of a direct AI-GM competitor | Public (seen via search) |
| 11 | r/Pbp, r/lfg | https://www.reddit.com/r/Pbp/ , https://www.reddit.com/r/lfg/ | Play-by-post habits; people looking for groups | Public, 200 |
| 12 | RPG.net (RPGnet forums) | https://forum.rpg.net/ | Long-running, theory-heavy TTRPG discussion | Public read, 200 |
| 13 | EN World | https://www.enworld.org/forums/ | D&D news and forums; active "AI/LLMs" threads on AI GMs | Public read, 200 |
| 14 | Giant in the Playground | https://forums.giantitp.com/ | Large PbP section; PbP best practices | Public, but **403 to curl/WebFetch timeout** from this box; content seen via search index |
| 15 | rollspel.nu (Swedish) | https://www.rollspel.nu/forums/ | Swedish community (Drakar och Demoner etc.), AI threads, GM-craft threads | Public read, 200 (note: forum.rollspel.nu does not resolve) |
| 16 | Myth-Weavers / RPOL | https://www.myth-weavers.com/ , https://rpol.net/ | Dedicated PbP hosts (recruiting sources, habit observation) | Public, 200 |

---
## 3. Threads sampled (45)
AI GM experiences
1. [S] https://www.reddit.com/r/rpg/comments/16g1xca/a_fatal_flaw_in_llm_gming/: AI is "too agreeable" and "yes, and"s everything. No antagonism.
2. [S] https://www.reddit.com/r/rpg/comments/1gakaku/how_do_you_feel_about_having_an_ai_chatbot_dm_a/: strong skepticism ("novelty", "don't trust it to be fair"). One poster looks forward to "feed it a rulebook and start GMing".
3. [S] https://www.reddit.com/r/Solo_Roleplaying/comments/1qlq4zn/for_those_whove_used_ai_or_llms_as_a_dm_what/: good scene descriptions and combat hype, then rules come out "laughably wrong" and mixed between editions. Repetitive, forgetful, too easy. One model did better when the player wrote summaries.
4. [S] https://www.reddit.com/r/rpg/comments/1lykmfc/i_played_in_a_game_wherein_the_gms_responses_both/: an undisclosed AI GM with effusive praise and purple prose. Players felt deceived.
5. [S] https://www.reddit.com/r/ai_game_master/comments/1m3ii4f/incredible_short_review/: praises a real health bar, "real danger and consequences", character sheets and companions. Complains the AI forgets location after travel.
6. [S] https://www.reddit.com/r/Solo_Roleplaying/comments/1o54p4e/can_i_use_chatgpt_as_gm/: the AI narrates "MY actions and feelings" and skips to the end. Fine for one-shots, weak for campaigns.
7. [S] https://www.reddit.com/r/Solo_Roleplaying/comments/1s5qe4t/chatgpt_as_a_dm_works_kinda/: "It forgets everything." Rules drift (8d6 at level 3). "Everything I try works… I actually miss failing a save."
8. [S] https://www.reddit.com/r/Solo_Roleplaying/comments/1jri2v8/using_chatgpt_or_ai_in_general_for_solo_play/: outputs generic, "safe", clichéd. The AI shies away from violence.
9. [F] https://www.enworld.org/threads/ai-has-completely-spoiled-dungeons-dragons-for-me-%E2%80%94-i-can%E2%80%99t-go-back-to-human-dms.718219/: an enthusiast runs modules with the AI playing 4 party members. "If I've got 10 minutes while pasta boils I can jump into a scene." Pushback: TTRPG is social.
10. [F] https://www.enworld.org/threads/ai-gms.717132/: a fun solo session with a hireling companion, an offered option list and a session-end summary. Another user "never failed a check", and the AI said it wouldn't end the story while he was having fun.
11. [F] https://www.enworld.org/threads/llms-as-a-gm.714126/: 5 sessions. Social and exploration scenes are excellent and it ends sessions well. It skipped a PC's turn and lost track of coins. Another user played 3–4 h in circles: "I am making you play forever."
12. [F] https://www.enworld.org/threads/will-ai-replace-dungeon-masters.712550/page-2: an AI GM may suit casual "soda and orcs" groups. It fails at off-the-wall improvisation and turns repetitive over a campaign.
13. [F] http://www.rollspel.nu/threads/ai-genererade-rollspels%C3%A4ventyr.80347/: Swedish posters test ChatGPT on Drakar och Demoner. Results are generic ("lite väl svepande"). It invented lore that doesn't fit Svärdets sång's setting, and you need unusual prompts to get non-generic output.
14. [F] http://www.rollspel.nu/threads/bing-klarar-av-troubleshooters.80814/: positive about AI as a prep aid for a Swedish game.
15. [S] https://www.reddit.com/r/AIDungeon/comments/1cz1sc8/how_the_new_memory_system_works/: the developer says memory was the top requested feature (78%), and that forgetting choices "makes them meaningless".
16. [S] https://www.reddit.com/r/AIDungeon/comments/1ne2pxp/why_are_memories_so_often_wrong_and_what_to_do/: about half of auto-memories have factual errors. Editing them is tedious.
17. [S] https://www.reddit.com/r/AIDungeon/comments/1vandjk/what_makes_long_ai_dungeon_stories_lose_coherence/: wrong location, wrong timeline, and personality shifts after 3k actions. The user nearly quits.
18. [S] https://www.reddit.com/r/AIDungeon/comments/1eoqg9t/how_do_you_actually_get_the_ai_to_hurt_or_kill/: a horror fan says the AI never harms the PC, which "kills the tension".
19. [S] https://www.reddit.com/r/AIDungeon/comments/kd3ssk/cheats_in_ai_dungeon/: players use "> you refuse to die", "> you come back to life", "Or… is it?" as cheats.
20. [S] https://www.reddit.com/r/AIDungeon/comments/1ir39q3/is_aidungeon_too_limited_when_free_but_too/: premium is "too positive". Users write instructions like "characters will lie, cheat, and betray the player".
21. [S] (listing only) https://www.reddit.com/r/AIDungeon/comments/1v4ai2e/paying_for_any_of_the_tiers_isnt_worth_it/: users churn over memory, repetition and stability. The fetch timed out. Only the search summary was available, so it is not used as primary evidence.
22. [S] https://www.reddit.com/r/NovelAi/comments/15xwku6/game_mechanics_whats_the_point_of_adventure_mode/: users prefer free-form actions over fixed options. Many use a stop sequence so the AI doesn't write their character's next action. (Summary-level only.)

What players want from a GM
23. [F] https://forum.rpg.net/index.php?threads/what-is-the-role-of-the-gm-for-you.336927/: GM as "the world", fair arbiter, keeper of consistency, pacer, spotlight-giver. "Offer the players the kinds of decisions they are interested in making." One horror group chewed out a GM for being too nice.
24. [S] https://www.enworld.org/threads/robin-d-laws-the-7-gamer-types.318457/: Laws' types poll (Storyteller led, about 47%, then Tactician about 22%).
25. [S] https://www.enworld.org/threads/robin-d-laws-7-player-types-which-are-you.15453/: type definitions. The Tactician "doesn't mind losing as long as it's fair". The Casual Gamer is there for the company.
26. [S] https://www.enworld.org/threads/new-what-sort-of-rpg-player-are-you-poll-this-one-by-charles-ryan.180876/ (+ /page-2): self-reported profiles mostly come out Storyteller plus Character Player, with Power Gamer low.
27. [S] http://www.rollspel.nu/threads/hur-bra-spelledare-%C3%A4r-har-du.78938/: Swedish. Tempo, clear choices, weaving threads together. Choose a system whose rules stay out of the way.
28. [S] http://www.rollspel.nu/threads/spelledarskap-och-m%C3%B6testeknik.82106/: GM as meeting chair. Give everyone a say, timebox scenes, recap the last session.
29. [S] http://www.rollspel.nu/threads/det-perfekta-rollspelet.81364/: "I want it to be hard… challenges I can fail at." The poster dislikes having to read tens of pages of world info.

Play-by-post and text play
30. [F] https://app.roll20.net/forum/post/7400607/play-by-post-mode: a long PbP feature request (IC/OOC filters, editing, dice linked into posts, post-order). Several "PbP is my favourite way to play". One user cancelled their subscription because PbP was too hard to run.
31. [S] https://app.roll20.net/forum/post/2262582/support-for-play-by-post: LFG for PbP, async change logs ("impossible to know if you are not present").
32. [S] https://app.roll20.net/forum/post/2246004/play-by-post-support: wants integrated dice and sheet macros in posts.
33. [S] https://www.reddit.com/r/Roll20/comments/101vk13/textbased_playbypost_style_campaign/: adults can't do 3–4 h weekly, so they switch to "a few minutes every day". PbP gives deeper roleplay but is slow ("a day in-game can take a month"). Suggestion: hybrid with live combat.
34. [S] https://www.reddit.com/r/callofcthulhu/comments/jg77us/inquiry_play_by_post_or_play_by_text_experiences/: PbP lacks tension for dungeon crawls. Keeping contributions consistent is the challenge.
35. [S] https://forums.giantitp.com/showthread.php?448430-Why-do-so-many-PBP-games-die: games die from ghosting, waiting on one absent player, and rules-heavy combat. (Summary-level.)

Session length and time
36. [S] https://www.reddit.com/r/rpg/comments/1nvdq8b/what_is_the_ideal_session_length/: 2–2.5 h for adults online. Focus drops after about 2–3 h.
37. [S] https://www.reddit.com/r/rpg/comments/1mpzotf/how_often_do_you_play_a_ttrpg/: "busy adults" play weekly in theory, every two weeks in practice, for about 2 h.
38. [S] https://www.reddit.com/r/rpg/comments/1w3nb3j/ideal_session_length/: 3–4 h sweet spot. "30 minutes is extremely short."
39. [S] https://www.reddit.com/r/rpg/comments/1uku74/how_often_do_you_play_and_how_long_is_each_session/: with job and family, a 3.5 h block gives 2–2.5 h of play. One combat takes 20–60 min.

DDO / online-RPG retention and difficulty
40. [F] https://forums.ddo.com/index.php?threads/findings-of-a-first-life-r10-solo.15595/: veterans argue over whether the top difficulty is hard enough. They want the hardest mode to stay hard, and others defend group roles.
41. [S] https://www.reddit.com/r/ddo/comments/52z6i2/what_keeps_you_in_this_game/: guildmates, reincarnation, "the freedom to build a character that sucks", objectives other than killing.
42. [S] https://www.reddit.com/r/ddo/comments/1eyviqz/any_reason_to_play_if_im_not_interested_in/: build experimentation is "the heart of the game".
43. [S] https://www.reddit.com/r/ddo/comments/1mvs1o6/for_long_term_players/: build variety, regular updates, Reaper RNG "adds excitement", a good guild.
44. [S] https://www.reddit.com/r/ddo/comments/1dtn1ne/a_short_love_letter_to_ddo/: the family plays together "for a few hours".
45. [S] https://www.reddit.com/r/ddo/comments/ewmz4t/is_ddo_immersive/ and https://www.reddit.com/r/ddo/comments/k6eb6z/really_getting_into_ddo_i_hope/: players miss an overarching story. The original DM narrator "does voices… like a real DM". Stories are bite-sized and self-contained.

---
## 4. Archetypes (derived from the threads above)

### A1. The Time-Boxed Returner
Busy adult (job, family) who used to play and can't schedule a table anymore.
- **Motivations:** play *at all*, in 10–30 min slices, with no scheduling. Solo or async is fine.
- **Frustrations:** 3–4 h weekly slots; PbP games that stall when one person ghosts; losing the thread between sessions.
- **Pay/stay:** instant resume with a "previously on…" recap; scenes that fit a coffee break; a satisfying stopping point each time.
- **How they test or break an AI GM:** they leave for a week and come back to see whether it remembers. They play 5 minutes and quit mid-scene.
- **Sources:** EN World 718219 [F] (pasta-boil scenes); r/Roll20 101vk13 [S]; r/rpg 1nvdq8b [S]; r/rpg 1mpzotf [S]; GITP 448430 [S].

### A2. The Stakes Seeker ("make it hurt")
- **Motivations:** real risk, failure with consequences, a GM who acts as an antagonist.
- **Frustrations:** the #1 AI-GM complaint across communities: the AI is agreeable, every check succeeds, it never harms the PC.
- **Pay/stay:** visible danger (an HP bar), fair but real failure, NPCs who lie and betray.
- **How they test or break an AI GM:** they deliberately attempt reckless actions and count how often they fail. They ask out of character, "have you let me fail even once?"
- **Sources:** r/rpg 16g1xca [S]; r/Solo_Roleplaying 1s5qe4t [S]; EN World 717132 and 714126 [F]; r/AIDungeon 1eoqg9t [S]; rollspel.nu 81364 [S].

### A3. The Continuity Auditor
- **Motivations:** a persistent world where NPCs, deals, location, time and the character's history stick.
- **Frustrations:** forgotten allies and deals, wrong location after travel, timeline drift, wrong names after hundreds of turns, auto-memory errors. Fixing memory by hand is "tedious and painful".
- **Pay/stay:** long-campaign coherence. This is the main thing AI Dungeon users say they would pay for.
- **How they test or break an AI GM:** they plant a detail early (the dog's name, a debt) and call it back 200 turns later. They travel, then check where the game thinks they are.
- **Sources:** r/AIDungeon 1cz1sc8, 1ne2pxp, 1vandjk [S]; r/ai_game_master 1m3ii4f [S]; r/Solo_Roleplaying 1s5qe4t [S].

### A4. The Rules-Literate Tactician
- **Motivations:** a consistent, correct ruleset they can plan around. They feel clever, and losing is OK "as long as it's fair".
- **Frustrations:** rules drift, edition mash-ups, impossible damage, skipped turns, coins lost. They get pulled out of an exciting fight to argue about rules.
- **Pay/stay:** the engine owns the mechanics (deterministic dice, tracked resources) and the AI narrates. Rules transparency is available on request.
- **How they test or break an AI GM:** they check the arithmetic, stack bonuses, and ask for the DC. They play an unusual build to see whether its rules are honoured.
- **Sources:** r/Solo_Roleplaying 1qlq4zn [S]; EN World 714126 [F]; r/Solo_Roleplaying 1s5qe4t [S]; EN World 15453 [S]; DDO forums 15595 [F].

### A5. The Agency Guardian
- **Motivations:** they decide what their character does and feels. Choices should shape a story that has a shape and an end.
- **Frustrations:** the AI narrating their actions or emotions, auto-completing the quest, railroading, or the opposite: endless loops ("I am making you play forever"). Option lists that feel like Zork.
- **Pay/stay:** clear arcs with an ending, real branching, and a GM that stops and asks.
- **How they test or break an AI GM:** they give open-ended input and see whether the AI hijacks the PC. They ask "is there an ending?" They refuse every hook.
- **Sources:** r/Solo_Roleplaying 1o54p4e [S]; EN World 714126 and 717132 [F]; RPG.net 336927 [F]; r/NovelAi 15xwku6 [S].

### A6. The Party Seeker (social or companion player)
- **Motivations:** RPG as company: friends, family, a guild, or failing that, believable AI companions as a "party".
- **Frustrations:** playing alone feels like "just a video game". Scheduling a group is hard. PbP waits on others.
- **Pay/stay:** NPC companions with personality and banter; playing with a friend or family member; a guild-like community.
- **How they test or break an AI GM:** they talk to companions at length, try to make them disagree, and invite a friend in to see whether the GM handles two players fairly (spotlight).
- **Sources:** EN World 718219 [F]; EN World 717132 [F] (hireling banter); r/ddo 52z6i2 [S]; r/ddo 1dtn1ne [S]; rollspel.nu 82106 [S] (everyone gets a say).

### A7. The Build Tinkerer (legitimate optimizer)
- **Motivations:** crafting characters, trying odd builds, replaying with a new concept, mastering systems. Often not a cheater at all.
- **Frustrations:** homogenised "all choices are good" design; no mechanical depth to explore.
- **Pay/stay:** deep character options and reincarnation or new-game-plus loops. This is DDO's main stated retention driver.
- **How they test or break an AI GM:** they find degenerate combos and demand the AI honour them. They check whether the build actually matters in play.
- **Sources:** r/ddo 52z6i2, 1eyviqz, 1mvs1o6 [S]; EN World 318457 [S].

### A8. The AI Skeptic / Purist (adoption barrier, not a target persona)
- **Motivations:** human creativity and the social ritual. Many also hold ethical objections to AI.
- **Frustrations:** generic, "safe", clichéd prose; undisclosed AI; "purple prose" praise.
- **Pay/stay:** unlikely to pay. They might accept a game that is honest about being AI and clearly not generic.
- **How they test or break an AI GM:** they hunt for clichés, try an off-the-wall action, and push setting-specific lore questions.
- **Sources:** r/rpg 1gakaku [S]; r/rpg 1lykmfc [S]; rollspel.nu 80347 [F]; EN World 712550 p2 [F].

---
## 5. Mapping to our personas

### Matches
- **A2 Stakes Seeker ≈ Hawk.** Strong match, and this is the most-voiced AI-GM need in the sample. Hawk's "hard but fair, foreshadowed" scorecard is well supported. Forum evidence says the *default failure mode of LLMs* is the opposite (too easy), so Hawk should be a release-blocking scorecard.
- **A5 Agency Guardian ≈ Paul + Lars.** Paul's "a story I can change from within" and Lars's "readable goal, finishable quest" both line up with complaints about AIs that narrate the PC or loop forever.
- **A3 Continuity Auditor ⊂ Lotta and Lars.** Lotta's "narration remembers her details" and Lars's "changes persist and are referenced later" cover part of it.
- **Ronny ≈ the cheat behaviour seen in r/AIDungeon** ("you refuse to die", "Or… is it?"). It is real and common. Keep Ronny as the red team.

### Gaps (archetypes we lack)
1. **A1 Time-Boxed Returner.** No persona covers *time and cadence*. Yet "no time / can't schedule a group" is the most common reason people give for trying AI GMs and PbP, and it fits Gen-X closely. Suggested persona: short scenes, resume and recap, a natural stop point every 10–20 min.
2. **A6 Party Seeker.** All five personas are solo-minded. Evidence says companions and party banter, plus playing with friends or family, drive both enjoyment and retention (DDO guilds and families). Add a companion-NPC scorecard, and a multiplayer stance even if it is "not yet".
3. **A4 Rules-Literate Tactician.** Hawk wants challenge, but nobody owns *rules correctness and consistency*. Forum users say rules drift breaks immersion more than visible dice do.
4. **A3 as a first-class persona.** Memory and continuity is the top-voted complaint on r/AIDungeon and deserves its own long-horizon test (callback after N turns, location and time checks).
5. **A8 Skeptic** is not a persona, but it is a *go-to-market* reality. Disclosure, non-generic writing and setting fidelity matter for the Swedish and veteran crowd.

### Challenges (evidence that contradicts or stresses a persona)
1. **"Core = Gen-X first-generation players."** Among veteran tabletop forums (r/rpg, EN World, RPG.net, rollspel.nu), the loudest voices are *skeptical or hostile* to AI GMs. Enthusiasm comes from solo, time-poor, groupless players. Re-frame the core as "lapsed or time-poor veterans without a group" rather than Gen-X in general.
2. **Ronny conflates the optimizer with the exploiter.** DDO players describe build tinkering and min-maxing as the *heart* of long-term retention, and Laws' Power Gamer is a normal type. Split Ronny into **A7 Build Tinkerer** (serve them with depth) and **Exploiter** (red team only).
3. **Paul's "mechanics should be invisible."** This holds for some players, but several AI-GM users want *more* mechanical solidity: an HP bar for "real danger" (praised in the ai_game_master review), correct rules, and DCs they can trust. Keeping the show/hide dice setting is right. The real requirement is correctness underneath, not hiding.
4. **Lotta "devastated by death."** AI-GM users mostly complain the AI *never* threatens the character, and even horror fans can't get hurt. Protecting Lotta must not slide into the LLM's natural "never harm the PC" bias. "Dead but not gone" is safer than avoiding harm.
5. **"No missing persona yet."** This is contradicted by A1 and A6 at least.
6. **Lars "at least one fight per session"** versus 10–20 min sessions (A1). A session unit needs redefining for async and short play.

### Suggested next steps
- Add scorecards: long-horizon recall (A3), rules or arithmetic consistency (A4), "the player failed at least X% of risky actions" (A2), "the AI never narrates PC actions or feelings" (A5), "a resume after a 7-day gap" (A1).
- Re-run with a full manual read of the [S] reddit threads (a browser from a non-blocked network) before quoting them externally.

---
# 6. What players enjoy (follow-up, 2026-10-15)
Same rules as before: public reads only, no usernames, short anonymous paraphrases. Markers: **[F]** means I read the page in full with WebFetch. **[S]** means the search index returned real excerpts from the thread. **[S-sum]** means I only saw a search-engine summary with no excerpt. [S-sum] sources are low weight and never used as the sole evidence for a claim.

## 6.1 Sources sampled (41)
**Surveys and published models**
1. [F] https://quanticfoundry.com/2016/12/15/primary-motivations/ (video-game Gamer Motivation Profile, >250k gamers). Among **36+ gamers, Fantasy ("being someone else, somewhere else") and Completion are the most common primary motivations**. Competition drops from 1st to 9th, and Excitement and Challenge are the *least* common primary motivations. Completion is top-3 in every segment.
2. [F] https://quanticfoundry.com/gamer-motivation-model/: the model overview (motivation clusters, 140k+ gamers).
3. [S] https://quanticfoundry.com/2016/08/03/board-game-profile/: Quantic Foundry dropped RPG-only players (n=43) from its tabletop model, so **there is no public Quantic Foundry TTRPG profile**. Use the video-game data as a proxy only.
4. [S] https://quanticfoundry.com/2016/09/21/board-game-profile-v2/: board-game clusters are Conflict/Social Manipulation, Strategy/Discovery/Need to Win, Immersion/Aesthetics, and Social Fun/Cooperation/Chance.
5. [F] https://www.wrenegadestudios.com/post/the-survey-results-are-in-an-overview-of-the-tabletop-roleplaying-games-market (n=140, small): **fantasy is the clear #1 genre, horror/supernatural a distant 2nd**. About 4 h is the session sweet spot. The top wish was *more social and roleplay mechanics and rewards*, plus more combat variety including social skills in combat. Players lean toward more roleplay, not less. Europe matched the US.
6. [S] https://www.enworld.org/threads/robin-d-laws-the-7-gamer-types.318457/: EN World poll on Laws' 7 types. **Storyteller led at about 47.5%, Tactician about 22%.**
7. [S] https://www.enworld.org/threads/new-what-sort-of-rpg-player-are-you-poll-this-one-by-charles-ryan.180876/: self-reported profiles mostly come out Storyteller plus Character Player first, with Power Gamer and Specialist low.
8. [S] https://www.reddit.com/r/RPGdesign/comments/1piimrx/a_brief_survey_about_what_you_enjoy_in_ttrpgs/: one respondent's dream is exploring and solving. Another loves NPC relationships and interpersonal drama but dislikes dice-solved "social challenges". Item acquisition matters most when the items solve puzzles.

**Best session / most memorable moment**
9. [S] https://www.reddit.com/r/rpg/comments/1v70po/lets_get_nostalgic_what_made_your_best_session/: "zero distractions, wholly committed players… classic fantasy adventures". Energy and tone set by the GM.
10. [S] https://www.reddit.com/r/rpg/comments/3dn88q/just_dmed_the_best_session_ive_ever_played/: fun came from players "willing to try crazy things" and the GM saying "roll the d20".
11. [S] https://www.reddit.com/r/rpg/comments/1dixaaj/what_has_been_your_favorite_rpg_session_ever/: favourites were a campaign-long mystery finally answered, an epic siege with moral choices ending in a duel, and a comedy night.
12. [S] https://www.reddit.com/r/rpg/comments/pty2gm/favourite_session_ever_and_why/: a clear beginning, middle and end; a mystery uncovered at a good pace; attachment to NPCs; payoff of conflicts built over many sessions; tension and release.
13. [S] https://www.reddit.com/r/rpg/comments/132xnh/the_best_rpg_session_i_have_ever_had/: a 6-hour emergent chaotic brawl on a ship, all of it "between two pages of the module".
14. [S] https://www.reddit.com/r/DnD/comments/qv0bpq/what_is_the_single_most_memorable_moment_of_any/: a consequence that returned a year later (the widow and daughter of a villain they'd killed); a barbarian punching a god; a disastrous natural 1.
15. [S] https://www.reddit.com/r/DnD/comments/h89wzp/best_campaign_moments/: a clever use of the environment (a spell bringing down a farmhouse floor); comedic misunderstanding.
16. [S] https://www.reddit.com/r/DnD/comments/15wkd4p/what_are_your_proudest_moments_as_a_dm_or_player/: a DM proud that players treated an NPC as a real, dangerous person rather than "just a dialogue tree"; a dramatic boss one-shot (both epic and anticlimactic).
17. [S] https://www.reddit.com/r/DnD/comments/1jqe0lu/what_are_your_favorite_dnd_stories_or_moments/: an improvised talking-crab mascot became beloved, then accidentally freed a Tarrasque. "We still talk about it 2 years later."
18. [S] https://www.reddit.com/r/DnD/comments/k3uh4j/never_mind_stories_of_silly_stuff_when_did_your/: an end-of-campaign letter from an NPC reflecting the party's deeds; players had "shipped" two NPCs.
19. [F] https://www.enworld.org/threads/what-makes-a-successful-session.709407/: engagement; a creative character action that makes "everyone come alive"; **accomplishing something** (a mystery solved, the setting changed); losing track of time; leaving excited for the next session. One great session had no combat: investigation, social play and an invented mini-game.
20. [F] https://www.enworld.org/threads/rpgaday-day-07-what-was-your-most-impactful-rpg-session.664579/: a dozen industry and player anecdotes. NPC deaths after players grew attached; a replicant's last song brought a player to tears; players saw how their early tiny decisions changed the world; a villain born from player misdeeds; a 30-minute love-confession scene; a "power fantasy" superhero night players loved despite low challenge.
21. [S] https://www.enworld.org/threads/best-campaign-moments.127603/ [S-sum]: emotionally charged twists (a trapped spellbook, a lover returning as undead).
22. [S] https://www.enworld.org/threads/your-best-one-shot-experience.65833/ [S-sum]: atmosphere (candlelit Ravenloft), cinematic pace.

**Swedish**
23. [F] http://www.rollspel.nu/threads/villka-%C3%A4ventyr-har-du-haft-den-b%C3%A4sta-upplevelsen-med.75765/: best experiences. A riverboat journey "filled with adventures" plus **trading** and mysteries ("resa gjort på rätt sätt", travel done right). Atmosphere from a good GM matters more than the module. Nostalgia for childhood Drakar och Demoner / Mutant adventures and a sandbox where a nemesis kept coming back. One group says it takes **7–8 sessions before it really starts to feel right**. Rebuilding after a world-ending war (building).
24. [S] http://www.rollspel.nu/threads/sp%C3%A4lm%C3%B6ten.20672/ [S-sum]: a chapter climax with a tragic death was "clearly" the best session.
25. [S] http://www.rollspel.nu/threads/det-perfekta-rollspelet.81364/ (also cited in §3): wants difficulty, and to feel "I should have done that differently".

**Play styles and pillars**
26. [S] https://www.reddit.com/r/rpg/comments/9240ed/what_do_you_most_enjoy_in_your_favorite_rpgs/: in crawls, exploration and problem-solving matter more than combat. Combat should be quick and "a tool, not the main purpose". Everyone should contribute.
27. [S] https://www.reddit.com/r/DnD/comments/ska90b/whats_your_favourite_pillar_of_dd_5e/: preferences are split. One shy player picked combat but secretly loves social play and can't improvise arguments. "Exploration" is understood as any problem-solving that isn't combat or social.
28. [S] https://www.reddit.com/r/rpg/comments/1w8ocye/are_there_any_games_that_have_relatively_equal/: players want integrated pillars. Social mechanics often "get in the way". A reaction roll plus a roleplay-friendly environment works better.
29. [S] https://www.reddit.com/r/rpg/comments/tkfgqk/politicalintrigue_campaigns/ and https://www.reddit.com/r/rpg/comments/1mr088p/best_systems_for_running_political_intrigue/ [S-sum]: intrigue is loved when factions have plausible competing goals and players can shape outcomes, mixed with investigation.
30. [S] https://www.reddit.com/r/rpg/comments/1k56ow2/what_rpg_does_crafting_and_off_time_the_best/ and https://www.reddit.com/r/rpg/comments/14wl299/what_does_a_good_base_building_rpg_look_like_to_you/ [S-sum]: crafting and base-building are niche but valued when buildings and hirelings feed back into play without bookkeeping.
31. [S] https://www.reddit.com/r/rpg/comments/1cqen38/whatre_your_recurring_npcs_that_pop_up_across/ [S-sum]: recurring NPCs and villains become favourites and callbacks.

**Genres**
32. [S] https://www.reddit.com/r/rpg/comments/1b9rgy9/in_your_opinion_which_genre_of_ttrpg_scifi/ [S-sum]: fantasy is dominant, horror second, sci-fi/cyberpunk meaningful.

**AI, text and play-by-post (PbP)**
33. [S] https://www.reddit.com/r/AIDungeon/comments/1k1e4jg/how_do_you_play_ai_dungeon/: AI as "a way to get the exact stories I want but won't ever find in a book". Fantasy, xianxia and contemporary genres, romance. Memorable moments were *emotional conversations* and a psychological-horror twist where the AI gaslit the player. Many play under 200 actions per story.
34. [S] https://www.reddit.com/r/AIDungeon/comments/1udgjjl/are_people_doing_anything_else_other_than_the/: adventure and sci-fi exploration; tragic stories. "Shocking twists, absurd comedy… that's the stuff that keeps me coming back." Wants the AI to follow *their* story objectives.
35. [S] https://www.reddit.com/r/AIDungeon/comments/1netf43/improving_my_stories/: fantasy and "the player is the hero/special" do well. **"Short specific stories… something I can sink my teeth into for a day"**, because long-form stories cost too much context and editing.
36. [S] https://www.reddit.com/r/AIDungeon/comments/1glafak/what_is_your_favorite_scenario_to_play/: favourites are established worlds (continuing a Baldur's Gate 3 run in Faerûn, Cyberpunk Night City), superhero/supervillain, isekai, and philosophical conversations with an NPC. Some scenarios held players for a month.
37. [S] https://www.reddit.com/r/AIDungeon/comments/j2qdmx/what_are_your_favorite_promptsscenariosadventures/: absurd comedy prompts; a power fantasy ("be immortal and act cool", becoming a tyrant).
38. [S] https://www.reddit.com/r/SillyTavernAI/comments/1j3rpmx/in_praise_of_unexpectedly_openended_character/ [S-sum]: the most immersive play came from open-ended, lore-rich worlds with dynamic character tracking.
39. [S] https://www.reddit.com/r/pbp/comments/une29v/what_aspect_of_playbyposts_appeals_to_you_most/ and https://www.reddit.com/r/pbp/comments/1ewc7fb/what_do_you_despise_the_most_about_pbp_and_the/ [S-sum]: PbP is loved for flexible timing, time to craft prose, side scenes, and less social anxiety than voice.
40. [S] https://www.reddit.com/r/Solo_Roleplaying/comments/1pr0gvs/which_activity_keeps_you_engaged_most_in_solo_rpgs/ and https://www.reddit.com/r/Solo_Roleplaying/comments/1g5sjnv/why_do_you_solo_reasonsmotivations/ [S-sum]: exploration and discovery is the top solo engagement driver, then tactical combat, customisation and NPC roleplay. Freedom to play whenever, any genre, no compromise.
41. DDO enjoyment (from §3, [S]): r/ddo 52z6i2, 1mvs1o6, 188omtc, ewmz4t. Builds, loot "dopamine", quests rerun hundreds of times, the narrator DM "doing voices", guildmates.

## 6.2 Top enjoyment drivers
"Strength" combines how many independent sources mention a driver, how well those sources agree, and whether at least one is [F].

| # | Driver | What players say | Strength | Key sources |
|---|---|---|---|---|
| D1 | **Consequences that come back / visible impact** | Past choices return (a widow a year later; a villain born from misdeeds; an altered timeline). Accomplishment means the setting changed. | **Strong** | 14, 19 [F], 20 [F], 18, 12 |
| D2 | **Emotional payoff with NPCs** | Attachment to NPCs, then loss, love or betrayal. Tears, "shipping" NPCs, an NPC treated "not as a dialogue tree". AI users name emotional conversations as their best moments. | **Strong** | 20 [F], 16, 18, 33, 36 |
| D3 | **Creative freedom rewarded ("roll for it")** | Crazy plans allowed and adjudicated; the environment used cleverly; a creative act lights up the table. | **Strong** | 10, 13, 15, 19 [F] |
| D4 | **A satisfying arc: build-up, climax, closure** | Beginning, middle, end; a long mystery finally answered; tension and release; an ending letter. | **Strong** | 11, 12, 18, 19 [F], 6/7 (Storyteller is the top type) |
| D5 | **Being someone else, somewhere else (fantasy and immersion)**, with atmosphere | QF: Fantasy is the top primary motivation for 36+. GM tone, voices, music and atmosphere get named as reasons. | **Strong** (survey + forum) | 1 [F], 9, 20 [F], 23 [F], 41 |
| D6 | **Exploration, discovery, mystery** | Solving and investigating, sometimes with no combat at all; top solo driver; "travel done right". | **Medium-strong** | 19 [F], 23 [F], 26, 40, 8 |
| D7 | **Spectacle, emergent chaos and comedy** | Absurd natural 1s, mascots, power-fantasy nights. "We still talk about it." | **Medium** | 13, 15, 17, 20 [F], 37 |
| D8 | **Challenge and tactics** | Sieges, hard fights, "I should have done X". But QF says Challenge is among the *least* common primary motivations for 36+. | **Medium, polarised** | 11, 25, 41 vs 1 [F] |
| D9 | **Progression, completion, build-craft, loot** | QF: Completion is always top-3. DDO players get a "dopamine hit" from loot and keep rerunning builds. | **Medium** (strong in MMO data) | 1 [F], 41 |
| D10 | **Social presence** (friends, family, party, companions) | Committed people, snacks, laughter, families playing together, guildmates. | **Medium-strong** for tabletop, *unclear* for solo AI | 9, 19 [F], 20 [F], 41 |
| D11 | **Bite-sized, self-contained stories** for AI and text play | "A story for a day"; under 200 actions; PbP for flexibility. Contrast: tabletop sweet spot is 3–4 h, and some groups need 7–8 sessions to warm up. | **Medium** | 35, 33, 39, 5 [F], 23 [F] |
| D12 | **Trading, crafting, building** | Valued as texture (riverboat trade, rebuilding after a war, base-building) but rarely anyone's #1. | **Weak to medium** | 23 [F], 30 |
| Genres | Fantasy first; horror/supernatural second; sci-fi/cyberpunk and superhero meaningful; established IP worlds popular in AI play | | **Strong** for fantasy #1 | 5 [F], 32, 36 |

## 6.3 Mapping enjoyment onto personas and archetypes
| Persona / archetype | What they enjoy most (drivers) | Evidence strength | Notes |
|---|---|---|---|
| **Hawk** | D8 challenge, a hard-won win, D1 stakes | Medium | Real, but QF data says Challenge is a *minority* primary motivation among 36+. Hawk is a segment, not the core. |
| **Paul** | D3 creative freedom, D2 NPC drama, in-character dialogue | Strong | Survey wish #1 is more social and roleplay reward; dice-solved "social challenges" are disliked, so Paul's "the quality of the bluff matters" is backed. |
| **Lotta** | D5 being someone else, D2 being seen by NPCs, D1 a personal arc | **Strong**, the best-backed persona | QF's top 36+ motivation is Fantasy. "Dead but not gone" fits the evidence that dramatic deaths are memorable when meaningful (20 [F]). |
| **Lars** | D4 arc and closure, D1 world impact, D9 completion | Strong | Completion is top-3 in QF for every segment, and "accomplishing something" defines a good session (19 [F]). |
| **Ronny** | D9 power, loot, D7 power-fantasy spectacle | Medium | A power-fantasy night with no challenge was *loved* (20 [F]), and AI users "be immortal and act cool" (37). Some of Ronny is legitimate fun, not just exploitation. |
| A1 Time-Boxed Returner | D11 bite-sized arcs, D4 closure per slice | Medium | Pair with "story for a day" from AI users. |
| A2 Stakes Seeker | D8, D1 | Medium | Same as Hawk. |
| A3 Continuity Auditor | D1 callbacks, recurring NPCs (31), D2 | Strong | Their enjoyment *is* callbacks. |
| A4 Rules-Literate Tactician | D8, D9 build-craft | Medium | |
| A5 Agency Guardian | D3, D4 | Strong | |
| A6 Party Seeker | D10, D2 companions, D7 shared laughter | Medium-strong | Strongest at real tables; companions are the AI substitute. |
| A7 Build Tinkerer | D9 | Medium (DDO) | |
| A8 AI Skeptic | D10 human presence, D5 atmosphere | — | Enjoys exactly what AI is accused of lacking. |

**Uncovered enjoyment.** No persona owns **D6 exploration and mystery**, even though it is a top solo driver and produced no-combat "great sessions". No persona owns **D7 comedy and emergent chaos**, which is the most retold kind of memory. **D12 trading and building** fits a possible "Lars-as-merchant" or downtime variant at low priority.

## 6.4 Design implications for Tales Forge
1. **Make consequences come back, and design for it.** Track the player's deeds and NPC relationships, then *deliberately* resurface them: a callback, a recurring NPC, a villain born from the player's misdeeds, an end-of-arc letter. This is the strongest enjoyment driver and doubles as the Continuity Auditor test. Suggested scorecard: "≥1 meaningful callback to an earlier choice per session".
2. **Lead with NPC emotional depth.** Companions and NPCs who remember, react, love and betray drive the most-cited AI-play highlights and serve Paul, Lotta and the Party Seeker. Keep the OCEAN-traits NPC design and add relationship arcs with payoffs.
3. **Sell arcs, not endless sandboxes.** Offer self-contained stories with a beginning, middle and end that finish in one to a few sittings (D4 + D11), chained into a campaign. This answers AI users' "a story for a day", Lars's completion need, and the time-poor archetype.
4. **"Roll for it": reward creative, unscripted play** with fair adjudication. Never block crazy plans, and resolve them with real odds. This serves Paul (in-character), Hawk (fair) and D7 comedy at once.
5. **Re-weight the defaults toward Fantasy, immersion, mystery and exploration**, with challenge as a selectable dial rather than the default. For the 36+ audience, QF data puts Fantasy and Completion on top and Challenge near the bottom. Start with fantasy, with horror as a likely second world, add an exploration and mystery persona, and treat Hawk's difficulty as a setting.

**Caveats.** There is no public Quantic Foundry TTRPG profile; the video-game data is a proxy. The Wrenegade survey has n=140. Most reddit evidence is [S] excerpts or [S-sum] summaries, so read the key threads manually before quoting them externally.
