---
title: Decision log
updated: 2026-10-13
---

# Decision log

Decisions made by the founders. Newest at the top. Each entry: date, decision, why, link to details. Changing a decision means adding a new entry that supersedes the old one.

Open questions waiting for a decision live in the [decision queue](../decisions/README.md); once decided, they are recorded here.

Ideas we may pick up later, not yet decided, live in [Future ideas](future-ideas.md).

## 2026-10-13: Character creation

- **Decision (fredrik@whyse.se, 2026-10-13, on the idea board):** build it. We need to have different models for character creation. where you can choose if you want a click-through creation or totally manually with dice rolls or just to give a description and a mix of these of course.
- **Why:** **Problem.** Today a player can make a character in one way only: the click-through screen with the 75-point buy. Some players want full control with dice. Other players want to describe the character in text and start fast.

**Goal.** After the world choice, the player selects a creation model. The models are click-through, manual with dice rolls, or description based. The player can mix the models. Each model makes a character that is legal for the world.

**Rules from the comments.**
- The player selects the world first. Then the player makes the character (Håkan). The game already uses this order.
- Solo play and group play use the same creation rules (Fredrik and Håkan, 2026-10-12).

**Founder answers (Håkan, 2026-10-12).**
- Dice rolls use 4d6 and remove the lowest die.
- Dice rolls permit one re-roll.
- In description mode, the player must approve the AI draft before play starts.
- Creation models are the same in every world by default. A new world may set its own model list.

**Proposed approach.**
1. One engine. All models make the same `TalesForge.CharacterCreation.Draft` in `lib/ex_tales_forge/character_creation/draft.ex`. All models end with `CharacterCreation.validate/1` and `finalize/1` in `lib/ex_tales_forge/character_creation.ex`.
2. Dice rolls. Add a `roll_stats/2` function to `CharacterCreation`. The server rolls 4d6 and removes the lowest die. The server stores the result in the draft. Put the roll method and the one-re-roll rule in a new `stat_roll` block in `priv/characters/creation.json`, next to `point_buy`. The stat range stays 3 to 18. Add a mode switch (point buy or roll) to `lib/ex_tales_forge_web/live/create_character_live.ex`.
3. Description based. Add a module `TalesForge.CharacterCreation.FromText` in `lib/ex_tales_forge/character_creation/from_text.ex`. It sends the text to the model through `TalesForge.LLM` in `lib/ex_tales_forge/llm.ex`. It gets back labels with a confidence value: race, class, occupation and skills. Where confidence is low, the AI asks one or two short questions. Where confidence stays low, the rules defaults fill the value. Then the code calls the normal `choose_race/2`, `choose_class/2`, `set_stat/3` and `set_skills/2` functions. Thus the rules check is the same. The player must approve the draft before play starts.
4. Mix. Each model opens the draft in the click-through screen. The player can change values before the game starts.
5. World defaults. All worlds permit all three models by default. A world may override the model list in its own data.
6. Tests. Add tests in `test/ex_tales_forge/character_creation_test.exs` for the roll and for the text step with the mock LLM. Run the playtest personas (`lib/ex_tales_forge/playtest/persona_characters.ex`) on each model.

**Acceptance criteria.**
- The player sees the creation models only after the world choice.
- Click-through works as it does today.
- In dice mode, the server rolls 4d6 and removes the lowest die for each stat. Each stat is from 3 to 18. The player may use one re-roll. A page reload does not give a new roll.
- In description mode, a text gives a full draft. The AI asks at most two questions. The player must approve the draft before play starts.
- Each draft passes `CharacterCreation.validate/1` before the game starts.
- The player can edit each draft in the click-through screen.
- Solo and group games use the same rules.
- All worlds share the same model list unless a world overrides it.
- Tests for each model pass in CI.

**Size: L.** Split it into three PRs: dice rolls (S), description based (M), mix and edit flow (S).

**Risks.**
- Each AI draft costs money. Mitigation: one AI call for each draft, and the mock LLM in tests.
- The AI can read the text wrong. Mitigation: the confidence value, the questions, the approve step and the edit step.
- Dice can give a weak character. Mitigation: one re-roll in `creation.json`.
- A longer flow can lose the draft on a page reload. Mitigation: keep the draft on the server.

**Deploy lane: normal.** The change is game code. Thus it goes to playtest first. Then a founder approves production.

**Confidence.** We have high confidence for dice rolls and the mix, because the engine has the functions now. We have medium confidence for the AI step. We will test that step with the personas. Verdict: feasible. Rough cost: L.
- **Link:** [the card on the idea board](https://tales-forge.fly.dev/team#idea-f9683a5d-ad23-48f3-89c4-b9b188e1366d)

<!-- board:idea:f9683a5d-ad23-48f3-89c4-b9b188e1366d -->

## 2026-10-13: Skill split

- **Decision (fredrik@whyse.se, 2026-10-13, on the idea board):** build it.
- **Why:** **Idea (Håkan).** A character with a high skill can split one action into two or more actions in one turn. Each part rolls at a part of the skill level. Example: one sword attack at 100 percent becomes two attacks at 50 percent. A foe can parry only one of them.

**Locked rules from the comments (Håkan, 2026-10-12).**
1. The split starts at level 20. Below level 30, the parts are always even: two parts at 10 each.
2. At level 30 or more, the player can split into three even parts. The player can also split into two uneven parts, for example 19 and 11.
3. The parts always sum to the skill level.
4. Every skill can split. A foe can split Dodge and parry more than one attack.
5. The split replaces the Multi-Actions rule (-2 for each extra action) in `combat.md`.

**How the dice work today.**
- The server rolls 1d20 for each check in `TalesForge.Game.Mechanics.perform_and_apply/4`. A roll equal to or less than the effective level succeeds.
- The effective level is the skill level plus the stat bonus.
- A natural 1 always succeeds. A natural 20 always fails, or gives a partial success from level 15.
- Today, a level above 20 gives no better odds. The split gives those levels a use.

**Proposed approach.** The game uses pure functions over plain data. The server makes all rolls. The GM only narrates them (call-type rule).
1. Rules text. Add one "Skill split" section to `priv/rules/core_mechanics.md`, because the rule covers all skills. Remove the Multi-Actions line from `combat.md`. Put a link to the new section there.
2. Thresholds. Keep the start level (20) and the triple level (30) in one setting. Thus the D100 card changes them in one place.
3. Split levels. Add a pure function `Mechanics.split_levels/2`. It takes the effective level and the split request. It returns the list of part levels, for example `[10, 10]` or `[19, 11]`. It rejects a split below the start level.
4. Intent. Jev gets a new field `split` with the values 1, 2 or 3. Uneven parts come from the player text, for example "a strong cut and a quick jab". The Elixir rules backup finds "twice" and "two attacks".
5. Rolls. `apply_server_mechanics/4` maps `perform_and_apply` over the part levels. It returns one resolution for each part. Each part uses the normal natural 1, natural 20 and partial success rules.
6. Learning. Each failed part banks a learning chance in the same skill. Case proposes a limit of one chance for each split action. Thus a split does not double the learning speed.
7. Skill meanings. Add a short table to `priv/rules/skills.md`. It gives the meaning of a split for each skill family. Examples: combat gives two attacks. Climb gives double climb speed. Lockpicking gives two locks. Persuasion gives two listeners. A skill with no entry uses the default: two separate attempts in the same turn.
8. Prompt. Add a prompt section that lists each part, its level and its result. The GM narrates each part. The GM does not invent a part.
9. Flag. The feature stays off until `SKILL_SPLIT=on` is set. When the flag is off, prompts and rolls stay the same.
10. Tests. Add doctests for `split_levels/2`. Add a turn test with injected rolls for a two-part attack and a three-part attack. Run the playtest personas with the flag on and off.

**Foe Dodge split.** The code has no parry roll yet. The parry formula is only in `combat.md`. Version 1 writes the foe rule in the rules text. The code follows when the server rolls parry for NPCs. That work is about size S on top of this card.

**Dependencies.**
- D100 card (`26706846`): Håkan wants skill levels from 1 to 100 on a d100. Then the split starts at 100 and the triple split starts at 150. Two even parts at 100 are 50 each.
- Case recommends to build this card after the D100 switch. Then Bobby writes all numbers and tests once, on the d100 scale.
- Bobby works on the Jev-first turn refactor and the prompt refactor now. This card adds one Jev field and one prompt section. Thus it fits after those pull requests.

**Reach.** The improvement roll stops at level 20 without a trainer. With a trainer, a skill can go to 26. A stat bonus of +4 can then give an effective level of 30. Thus the triple split is rare. The founders must choose if the raw level or the effective level unlocks the split.

**Acceptance criteria.**
- A player at level 20 types "I attack twice". The server rolls two attacks at 10 each. The GM narrates two results.
- A player below level 20 cannot split. The GM tells the player why in the story.
- A player at level 30 can split into three even parts or two uneven parts. The parts sum to the level.
- A split action banks at most one learning chance.
- When the flag is off, the production prompts and rolls stay the same.

**Size: M.** The rule function and the rolls are small. The Jev field, the skill table and the tests need most of the work.

**Risks.**
- Jev can see a split where the player wants one action. Mitigation: the GM states the part chances before the roll. A low-confidence split falls back to one action.
- The split can make high-level fights too strong. Mitigation: run the playtest personas against the parry rule before a founder approves production.
- Some skills have no clear split meaning. Mitigation: the default rule covers them. Founders add table entries over time.

**Deploy lane: normal.** The change is game code. It goes to playtest first. Then a founder approves production.

**Confidence.** Case has high confidence in the split rule and the rolls. Case has medium confidence in the Jev field, because the split wording varies a lot. Verdict: feasible with caveats. Rough cost: M.
- **Link:** [the card on the idea board](https://tales-forge.fly.dev/team#idea-9915480a-3275-4c78-9278-389cd05b9c69)

<!-- board:idea:9915480a-3275-4c78-9278-389cd05b9c69 -->

## 2026-10-13: Session versus canon

- **Decision (fredrik@whyse.se, 2026-10-13, on the idea board):** build it. Part 5 of 5 from the World building card. Rough cost: M.
- **Why:** **Problem.** Session play writes new facts into the database. Canon stays in the world seed files. Founders have no review list that compares one session with canon.

**Goal.** A founder opens a review list for one session. The list shows each difference with canon. For each difference, the founder selects Keep as session-only, Add to canon, or Mark as an error. Only a founder can change canon.

**Rules from the card and the parent.**
- Canon is the world seed in the repo. Each game session lives in the database.
- Founders promote good session facts into the world seed.
- This card is part 5 of 5 from World building. Build it after World definition, World seed format, Continuity check and Founder world editor.

**Existing code (high confidence).**
1. `session_events` stores play facts per session. Kind `world_fact` holds facts from `TalesForge.World.Extract`.
2. `TalesForge.World` loads pack facts from `priv/adventures/<id>/world_agents.json`. Agents hold pack facts and session facts.
3. The ADR `design-game-data-vs-sessions.md` already sets game data in git and sessions in Postgres. It also allows export of a session back toward a seed.
4. Continuity check (card 3) blocks bad writes at edit time. This card reviews what play already wrote.

**Plan.**
1. Add one pure function that diffs one session against its pinned seed. Inputs are plain structs. Output is a list of difference structs.
2. For structured facts, Elixir does the diff. It compares entity ids, places and typed `world_fact` rows with the seed.
3. For free text that has no clear entity, one Jev call assigns a fixed label to each leftover. Labels are new_npc, changed_place, conflict or other. Jev does not write prose.
4. Show the list in the founder tools, next to the world editor. Each row has the three actions from the card.
5. Keep as session-only stores a founder decision on that difference. The session stays as it is.
6. Add to canon writes a seed change through the same path as the world editor. A founder must confirm the write.
7. Mark as an error records the error. See open question 3 for the session side.
8. Put model calls and file writes at the edges. The turn pipe does not run this review.

**Call-type rule.** Structured session rows versus structured seed fields are a function call. Classification of leftover free text is a Jev call. An LLM does not invent canon text.

**Architecture.** Data, then pure transforms, then data. One module owns the diff. One module owns the founder decision write.

**Risks.**
- A large session can flood the list. Mitigation: group by entity and cap the first page.
- Add to canon needs the seed schema and the editor write path. Mitigation: ship this card last in the agreed order.
- A bad promote can break Tin Valley. Mitigation: founder confirm, and prefer a pull request for the first version.

**Confidence.** High confidence in the split of canon and session, and in reuse of `session_events` and `TalesForge.World`. Medium confidence in the cost until the seed write path is fixed on the editor card.

**Verdict.** feasible_with_caveats. The pieces exist. The caveats are seed format, editor write path, and a clear hybrid of Elixir plus Jev. Verdict: feasible with caveats. Rough cost: M.
- **Link:** [the card on the idea board](https://tales-forge.fly.dev/team#idea-9616b9a0-7656-407b-bb02-da4aba208908)

<!-- board:idea:9616b9a0-7656-407b-bb02-da4aba208908 -->

## 2026-10-13: World building

- **Decision (hawkan.fredriksson@gmail.com, 2026-10-13, on the idea board):** build it. We need to create some world building tool. How we create a world, what should be created, what should automatically be added. How we extend the world later on.
- **Why:** **Problem.** Founders cannot create or extend a world today. A world lives in an adventure pack in `priv/adventures/<id>`. Founders must edit the pack files by hand.

**Goal.** Founders create a world in a World building menu with a clear path. The game checks new content against the world. Founders decide which session facts become canon.

**Rules from the comments.**
- Founders build worlds first. Paying players build worlds later. This is a business decision (Fredrik).
- The pack files are the world seed. Each game session is an instance in the database (Fredrik).
- A world seed holds scenography, main characters with their means and motives, supporting cast, synopsis and hooks (Fredrik).
- The world type controls what the game can add in play. A murder mystery defines the full cast. A general fantasy world permits the game to add minor NPCs, for example smiths and bakers (Fredrik).
- We extend Tin Valley first. Tin Valley stays separate from the production tool. Founders can delete Tin Valley or make it inactive later (Håkan).
- A world has one of three scopes: Adventure, Region or Universe (Håkan, 2026-10-12).
- The base game has five skill groups: Martial, Finesse, Social, Knowledge and Craft. A world can rename skills and add its own skills (Håkan, 2026-10-12).
- Races and character types belong to each world.
- Each world has a theme text. Founders can add to the theme text at any time (Håkan, 2026-10-13).
- Founders use a review list to promote good session facts into the world seed (Håkan, 2026-10-13).

**Creation path (agreed by Håkan, 2026-10-13).**
1. Choose a scope: Adventure, Region or Universe.
2. Describe the setting and write a short theme text.
3. Choose skills from the five groups. Add races and character types for this world.
4. Add important NPCs, locations and factions. Founders can add more later.
5. Save the world seed. The continuity check then uses this seed.

**Proposed split into five cards.**
1. World definition (S). Each world states its scope.
2. World seed format (S-M). One schema in one place for the canon files and the theme text. Packs, the editor and the game read the same shape. Tin Valley moves to this format first.
3. Continuity check (M). A Jev call compares new content with the seed, the newest theme text and a short world summary. The call returns "consistent" or a list of conflicts with reasons.
4. Founder world editor (M). The creation path above, as a menu on `/admin`.
5. Session versus canon (M). A Jev call compares one session in the database with canon. A founder approves each change to canon in the review list.

Recommended order: 1, 2, 3, 4, 5. Cards 1 and 2 are the base for the other cards.

**Existing code.** `TalesForge.World`, `TalesForge.World.Extract` and `TalesForge.World.Agent` already hold world facts. `world_agents.json` holds the facts for each place and person. Fronts hold the factions and their plans. The skill groups are in `priv/rules/skills.md`.

**Architecture.** Each step is a pure function over plain structs. The model calls and file writes stay at the edges.

**Risks.**
- One model call cannot read a large world in full. Mitigation: keep a short world summary and update it after each change.
- The game can change canon by mistake. Mitigation: a founder approves each change to canon.

**Confidence.** High confidence in the creation path and the split. Medium confidence in the cost of the continuity check for Universe scope. Verdict: feasible with caveats. Rough cost: L.
- **Link:** [the card on the idea board](https://tales-forge.fly.dev/team#idea-eb7c0641-a3ed-4ac2-b002-ddff6dfe3fc2)

<!-- board:idea:eb7c0641-a3ed-4ac2-b002-ddff6dfe3fc2 -->

## 2026-10-12: high vs low skills storytelling

- **Decision (fredrik@whyse.se, 2026-10-12, on the idea board):** build it. A character with high skills (experience) notices more and should get more detailed storytelling
- **Why:** **Problem.** Today the GM gets the skill, the roll and the outcome. The GM uses them for tone only. A novice and an expert see the same scene.

**Goal.** The skill level changes how much the character notices. A low-skill character sees only the main threat. A high-skill character sees one or two useful details. The player can use these details in the next action.

**Rules from the comments.**
- The rule applies to all skills (Fredrik, 2026-10-12).
- The skill level sets the base detail level. A large success adds one more detail (Case proposal, Håkan agreed on 2026-10-12).
- Each detail must be true in the world state. The GM must not invent a weakness.

**Examples.**
- Unarmed combat: a high-skill character sees that the opponent is off balance. A low-skill character sees only the fists.
- Lockpicking: a high-skill character notices that one pin is stuck.
- Persuasion: a high-skill character sees that the guard is tired.

**Proposed approach.** The server selects the details. The GM only narrates them (call-type rule).
1. Detail level. Add a pure function `TalesForge.Game.Notice.level/1` in `lib/ex_tales_forge/game/notice.ex`. The function reads the `MechanicalResolution` (skill, roll, `effective_skill` and outcome). It returns `:low`, `:medium` or `:high`.
2. Thresholds. Put the thresholds in one data file, `priv/rules/detail_levels.json`. Start values: an effective skill of 0 to 5 is low. A value of 6 to 11 is medium. A value of 12 or more is high. A success with a margin of 5 or more adds one detail. A natural 1 also adds one detail.
3. Detail pool. Add `Notice.details/3`. It takes the world state, the skill and the level. It returns 0, 1 or 2 true details. The sources are NPC data that the server has now: mood, personality traits and concerns. A front fact can also have an optional `notice` field with a skill and a minimum level. The function selects only details that the player does not see now.
4. Pipeline. The turn calls `Notice` after the mechanics stage and before the narration. This step is a pure function over plain data. The turn writes the details into the outcome record. Thus the turn log shows them.
5. Prompt. Add a section `TalesForge.Prompt.Sections.NoticedDetails` in the `:turn` slot. The section lists the level and the details. At the low level, the GM narrates tunnel vision and time pressure. At the high level, the GM narrates calm focus and the listed details. The GM narrates no other hidden fact.
6. Flag. `TalesForge.Prompt.Profile` adds the section only when the flag `SKILL_DETAIL_LEVEL=on` is set. When the flag is off, the GM prompt stays byte-identical.
7. Tests. Add doctests for `level/1` and `details/3`. Add a test that shows a hidden detail in the prompt only at the correct level. Run the playtest personas with the flag on and with the flag off.

**Case recommendations for the open questions.**
- Turns with no roll: the perception skill sets a passive level, one level lower than a roll.
- A failed roll keeps the base level from the skill. The failure itself is the cost.
- The game shows the details in the story text only. Then the story stays natural.

**Acceptance criteria.**
- The same action gives less detail at a low skill and more detail at a high skill.
- Each detail in the narration comes from the world state.
- A low-skill turn shows no hidden detail.
- When the flag is off, the production prompts stay the same.

**Timing.** Bobby works on the prompt refactor now. The refactor gives each prompt section its own module (#208). This card adds one new section. Thus Bobby builds it after the refactor.

**Size: M.** The prompt section is small. The detail pool and the thresholds need most of the work.

**Risks.**
- The world data has no combat details today, for example "favors the left side". Mitigation: version 1 uses NPC mood, traits and concerns. World authors add `notice` facts later.
- The GM can add details that are not in the list. Mitigation: a clear prompt rule and a log-only check in `TalesForge.Game.ProseCheck`.
- More text in the prompt adds tokens. Mitigation: a maximum of 3 short lines for each turn.

**Deploy lane: normal.** The change is game code. Thus it goes to playtest first. Then a founder approves production.

**Confidence.** We have high confidence for the level function and the prompt section. We have medium confidence for the detail pool, because the world data has few hidden details now. Verdict: feasible with caveats. Rough cost: M.
- **Link:** [the card on the idea board](https://tales-forge.fly.dev/team#idea-72996ae0-5af7-4e4c-b1a0-ab6d6330843a)

<!-- board:idea:72996ae0-5af7-4e4c-b1a0-ab6d6330843a -->

## 2026-10-12: Temporary notification pop-ups

- **Decision (fredrik@whyse.se, 2026-10-12, on the idea board):** build it. notifications should be temporary pop-ups "Card created" just like when connection is lost
- **Why:** Confidence: high. The change uses only parts that exist in the code today.

What exists today:
- The connection-lost pop-up is `#client-error` in `Layouts.flash_group/1` (`lib/ex_tales_forge_web/components/layouts.ex`).
- `#client-error` uses the `flash/1` component in `core_components.ex`. That component shows a daisyUI toast at the top right of the page.
- `TeamLive` already renders `Layouts.flash_group/1` on `/team`.
- The "Card created" notice is a box (`#board-notice`) under the New idea form in `TeamIdeaBoard`. It stays until a founder clicks ×.
- No other success notice on the board uses a pop-up today.

What to build:
1. Show the "Card created" notice with the `flash/1` component, as `#client-error` does.
2. Keep the id `board-notice`, the text "Card created:" and the link that opens the new card.
3. Add an `autohide` attribute to `flash/1`. Its default value is false.
4. Add a colocated JS hook next to `flash/1` for `autohide`. The hook closes the toast after 5 seconds.
5. Stop the timer while the pointer or the keyboard focus is on the toast.
6. Send the board event `dismiss_notice` when the toast closes. The server then clears `@notice`.
7. Keep error messages open until a founder closes them.
8. Update the `#board-notice` tests in `team_idea_board_test.exs`. Add a test for the `autohide` markup.

Where it lives: the toast look and the timer live in one place, `flash/1`. Other pages keep their messages as they are now. The change adds no LLM call and does not change game code. Verdict: feasible. Rough cost: S.
- **Link:** [the card on the idea board](https://tales-forge.fly.dev/team#idea-1a49bfc9-fd72-4bbd-b3ff-1b961dffa2c2)

<!-- board:idea:1a49bfc9-fd72-4bbd-b3ff-1b961dffa2c2 -->

## 2026-10-12: Code heat map shows no data in playtest

- **Decision (fredrik@whyse.se, 2026-10-12, on the idea board):** build it. the code heat map on playtest never shows any data, i think there is an unclear sampling req.
- **Why:** Verdict: feasible. The cause is clear, and the fix is small (high confidence).

Cause (high confidence):
1. `TalesForge.CodeHeat.Sampler` keeps the call counts in process memory.
2. The sampler writes its first sample only after 24 hours (`:sample_every_ms`).
3. A deploy or a restart of `tales-forge-playtest` stops the sampler. Then the counts in memory are lost.
4. The playtest app gets a deploy after each green CI run on main.
5. Since the heat map merge (#159, 2026-10-10 16:58), the longest gap between merges on main is about 8 hours.
6. Thus the sampler never runs for 24 hours. The table `code_heat_snapshots` stays empty.
7. The page shows "There is no sample yet". After each restart, the page shows a new time for the first sample.
8. This 24-hour rule is the sampling rule that the card calls unclear.

PR #161 and PR #168 changed only the page layout (390 px, legend, first sample time). They did not change the sampler.

Fix:
1. Change the sampler to write one sample each hour, at each `:read`. Each sample holds the counts of one hour.
2. Write the current counts in `terminate/2` when Fly stops the machine. Then a deploy loses no counts.
3. Add `kill_signal = "SIGTERM"` and `kill_timeout = "30s"` to `fly.playtest.toml`, as in `fly.toml`.
4. Add one pure function in `TalesForge.CodeHeat` that merges the samples of a time window into one list of rows.
5. Let the page pipe these rows into `tiles/4`, as it does now.
6. Show the last 24 hours as a rolling window. The map then shows data one hour after a deploy.
7. Change `:keep` from 14 samples to 72 samples (3 days of hourly samples).
8. Change the page text to "A task writes one sample each hour. The map shows the last 24 hours."
9. Remove the text that promises the first sample 24 hours after the start.
10. Keep the heat map off on production. `enabled?(:production)` stays false.
11. Add tests for the hourly write, the write at stop, the merge of a window and the empty window.

Design notes:
- The data flow is data, then pure transforms, then data. The trace and the database write stay at the edge, in the sampler.
- `TalesForge.CodeHeat.save/4` stays the one place that writes samples. The table needs no migration.
- Today `fly.playtest.toml` has no `kill_signal`. Fly then sends its default signal. Then `terminate/2` does not run (medium confidence).
- One sample keeps at most 2000 functions (`:max_rows`). 72 samples use at most about 25 MB in the playtest database (medium confidence).
- The fix reaches playtest only with a playtest deploy. Bobby needs a founder OK for that deploy.
- Check: one hour after the deploy, Gentry opens `/admin/operate/code-heat` on playtest and sees tiles. Verdict: feasible. Rough cost: S.
- **Link:** [the card on the idea board](https://tales-forge.fly.dev/team#idea-3281c539-1373-4fc3-9aa9-664c717f836b)

<!-- board:idea:3281c539-1373-4fc3-9aa9-664c717f836b -->

## 2026-10-12: Expand goals to add/subtract tasks

- **Decision (fredrik@whyse.se, 2026-10-12, on the idea board):** build it. clicking on a goal should expand it so we can add and subtract tasks that needs to be done to achieve the goal
- **Why:** **Problem.** A founder sees the progress on a goal, but cannot see or change its cards from the goals strip. Today a founder opens each card and picks a goal from the Goal list.

**Goal.** A founder clicks a goal and the goal opens. The open goal shows its cards. The founder can add a card to the goal and can remove a card from the goal.

**What we have today.**
- `TalesForge.Board.Goals` stores goals. It counts Done cards over all cards for each goal. Archived cards are not counted.
- A card has zero or one goal (`board_ideas.goal_id`).
- `Goals.set_card_goal/3` sets or clears the goal. Only a founder can do this.
- The Goal list on an open card already calls that function.
- The goals strip (`TeamGoals`) shows votes, the progress bar and the countdown. It does not open.

**Assumption.** A task under a goal is an idea-board card that has that goal. Progress already uses those cards. We do not add a second task list.

**Proposed approach.**
1. Make each goal row a control that opens and closes.
2. Show the cards for that goal in the open panel. Show the title, the column and Done or not Done.
3. Add a card: let the founder pick an unassigned card. Call `Goals.set_card_goal/3`.
4. Remove a card: clear the goal on that card with the same function.
5. Keep one place for the goal link: `board_ideas.goal_id`. Do not add a second task table.
6. Keep the Goal list on the open card. Both UIs call the same function.
7. Update the progress bar from the existing `Goals.strip/1` counts after each change.

**Acceptance criteria.**
- A founder clicks a goal and sees its cards.
- A founder adds an unassigned card to the goal from the open panel.
- A founder removes a card from the goal from the open panel.
- The progress counts update after add and remove.
- The layout works at 390 px phone width.
- Bots and the QA session still cannot change a card's goal.

**Size: S.**

**Risks.**
- A long card list on a small screen. Mitigation: show a short list with a Show all control, or a sheet on phone.
- Two UIs for the same change. Mitigation: both call `Goals.set_card_goal/3`.

**Deploy lane: admin / team tools.** Ship to playtest first. Then a founder approves production.

**Confidence.** High confidence. The data model already supports this. The work is mostly UI. Verdict: feasible. Rough cost: S.
- **Link:** [the card on the idea board](https://tales-forge.fly.dev/team#idea-79643925-9725-4824-bbe1-42b2efb20965)

<!-- board:idea:79643925-9725-4824-bbe1-42b2efb20965 -->

## 2026-10-12: Work time auto log

- **Decision (fredrik@whyse.se, 2026-10-12, on the idea board):** build it.
- **Why:** **Problem.** Founders need a fair work time log for Slicing Pie. The app does not log founder work time today.

**Goal.** The app logs work sessions for each founder. The log supports fair hour shares in the Slicing Pie spreadsheet.

**Rules from the comments.**
- Start a session when a founder edits a card or plays on playtest or prod (Fredrik, 2026-10-12).
- Check activity every 15 minutes. Close the session when the founder is idle (Fredrik).
- Idle limit is 15 minutes (Håkan).
- Founders can add time by hand with a short reason (Håkan).
- Reading alone does not count in v1. Comments and card moves cover that work (Håkan and Case).
- All founders see the full log in a menu on `/team` (Håkan).
- Each log entry stores a short note of the work (Håkan).
- Ownership uses the Slicing Pie model and the existing spreadsheet (Fredrik, 2026-10-12).

**Proposed approach.**
1. Store activity events. Each founder action writes one event with author and time. Do not use an in-memory timer. A deploy clears memory. Stored events stay correct after a restart.
2. Count actions, not open pages. `TalesForgeWeb.Presence`, `TalesForge.Online` and `TalesForge.TeamOnline` show open pages. An open page is not work.
3. Actions in v1. Card comments (`TalesForge.Board.Comment`), card moves (`TalesForge.Board.Transition`), team chat (`TalesForge.Chat.Message`), card text edits and game turns on playtest or prod.
4. Add author and time where missing. Card text edits and `TalesForge.Schemas.Turn` do not store the founder today. Add that data before we compute sessions.
5. Playtest events reach prod. Prod already reads playtest through `TalesForge.Online.Peer` and `TalesForge.Costs.Peer`. Add the same peer pattern for activity events.
6. Compute sessions from events. A session starts at the first action. The session ends at the last action when no new action arrives for 15 minutes. The idle gap does not count.
7. Manual entries. A founder adds hours, a date and a short reason. Use this for work outside the app and for old spreadsheet hours.
8. Work notes. Auto sessions list the action types. Manual entries keep the reason text.
9. Export. Each month a founder exports hours as CSV. One row per founder and day. Paste the totals into the Slicing Pie spreadsheet.
10. Record the Slicing Pie rule in `decisions.md` before build starts.

**Acceptance criteria.**
- A founder action on the board or in play creates an activity event with author and time.
- A session starts at the first action and ends at the last action after 15 minutes with no action.
- The idle 15 minutes do not add to the logged time.
- A founder can add time by hand with a reason.
- All founders can open the full log from a menu on `/team`.
- Each entry shows a short work note.
- Prod includes playtest activity events.
- A CSV export lists hours per founder and day.
- Reading a card alone does not create an event in v1.

**Size: M.**

**Risks.**
- Card text edits and game turns lack founder today. Mitigation: add author and time in the first PR.
- Playtest is a separate app. Mitigation: reuse the peer pattern from `Online.Peer` and `Costs.Peer`.
- Work outside the app stays invisible. Mitigation: manual entries with a reason.
- Deploy restarts clear memory. Mitigation: compute sessions from stored events.

**Deploy lane: normal.** Team tools change. Ship to playtest first. Then a founder approves production.

**Confidence.** High confidence on the event design and the session rules. Medium confidence on the source of truth after go-live until founders answer that question. Verdict: feasible with caveats. Rough cost: M.
- **Link:** [the card on the idea board](https://tales-forge.fly.dev/team#idea-e1fa4220-7e9e-43a2-924f-9ac3ebee11fa)

<!-- board:idea:e1fa4220-7e9e-43a2-924f-9ac3ebee11fa -->

## 2026-10-12: Turn architecture: one pipe over a %Turn{} struct

- **Decision (Fredrik, 17:50):** each turn is one pipe over a `%Turn{}` struct:
  `input |> Jev.classify() |> Premise.check() |> Mechanics.apply() |> Npcs.react() |> Prompt.build() |> Gm.narrate() |> Outcome.persist()`.
  1. Every stage takes the struct and returns it.
  2. Stages are pure. IO (LLM, DB, PubSub) sits at the edges or behind a small adapter in the struct or the options, so tests need no mocks.
  3. No ad hoc `Map.put`: each stage writes its own typed field (`turn.intent`, `turn.premise`, `turn.outcome`, `turn.npcs`, `turn.prompt`, `turn.narration`).
  4. Pattern matching and function heads, not if/case chains. `{:ok, _}`/`{:error, _}` with `with`. A rejected action is data on the struct, not an exception.
  5. Flags and the app role are read from config into the struct once, at the start.
  GM streaming stays: `Gm.narrate` takes a stream adapter that emits partial text, and it starts only after `Npcs.react` returns. The 600 ms NPC timeout lives inside the NPC adapter.
- **Why:** one readable shape for the turn, testable without mocks, and each stage owns its data.
- **Details:** [Architecture](architecture.md)

## 2026-10-12: Unskilled wage and catalogue v2 rules

- **Decision (Fredrik, 17:17): the unskilled wage comes from the price formula.** The economy rules anchor every price in labour: **1c = ~20 minutes of unskilled work** (`rules/economy.md`, "In Our System"). One hour of unskilled labour is therefore **3 copper**, and an 8-hour day is 24c. The `work` action pays this wage for each game hour. The wage is in the world config (`economy.unskilled_wage_copper_per_hour: 3` in the adventure front matter). Modifiers for skill, danger and region come later. The services table line "Unskilled labor (day) 5-10c" contradicted the anchor; it now reads 3c per hour and 24c per day.
- **Decision (Fredrik, 17:21 to 17:33): catalogue v2 rules.**
  1. **NPC refusal:** NPCs may refuse gifts and trades because of their personality or traits.
  2. **Manner adverbs:** manner adverbs (quickly, carefully, quietly) change both the time and the roll odds. The server applies them from an adverb table. **The adverb table is PROVISIONAL** (for example: quickly ×0.5 time and −2 to the roll; carefully ×1.5 time and +2; quietly ×1.25 time and +1, stealth mode; with ask, say or tell it means private speech and has no modifier). Jev outputs family + mode + manner.
  3. **Area inventories:** forests and other areas hold limited inventories. Finding things or killing game needs a roll.
  4. **Skill synonyms:** Jev gets a synonym set for each skill, built from English verb frequency lists. The frequency data is wordfreq (Robyn Speer), CC BY-SA 4.0; see [Credits](credits.md).
  5. **Skill list v2:** five domains. New skills: sleight_of_hand (includes pickpocket), acrobatics, perception (takes search, spot and notice from insight), performance, medicine and appraisal. **There is no general crafting skill.** Craft has smithing, carpentry, leatherworking, cooking (simple meals need no roll) and alchemy. Files: `skill-list-v2.md`, `skill_synonyms.v2.json` (full, server side) and `skill_synonyms.v2.trim.json` (Jev prompt).
  6. **Bargaining (numbers approved):** haggling is a persuasion roll. Appraisal is a separate, optional roll that tells the true value, the scarcity and the fair local price. Knowing the price gives +2 to persuasion (+3 at appraisal 10 or higher), and the haggle then starts from the fair price. A success moves the price 10 to 20 %. A failure caps the deal at the fair price minus 10 %.
  7. **Growth:** a skill grows only from failures in that exact skill.
- **Why:** Fredrik settled the open questions in `action-families.md` §6 so that catalogue v2 (turn pipeline step 5) can start.
- **Details:** [Design: the turn pipeline](design-turn-pipeline.md), §8 step 5

## 2026-10-12: Turn pipeline: provisional rules (PROVISIONAL)

- **Decision (Fredrik, PROVISIONAL):** These rules settle gaps in the turn pipeline design until a full decision replaces them. The code is `TalesForge.Game.TurnRules` (ex-tales-forge PR 3, flag `TURN_STATE_FROM_MECHANICS`).
  1. **PROVISIONAL:** Game minutes per action use the existing clock costs (15 minutes for one plain action; wait and train use their own time). Each new catalogue action gets a placeholder: `rest` 60, `work` 60, `equip` 15, `give` 15. There is no full time table.
  2. **PROVISIONAL:** A `none_fits` turn does not move the clock.
  3. **PROVISIONAL:** Jev plays at most 3 ordered actions. The server drops a 4th action, and the GM gets a note.
  4. **PROVISIONAL:** An NPC repeat is an exact match after the server lowers the case and collapses the whitespace.
  5. **PROVISIONAL:** "Pay for a room" with nobody here who rents rooms is rejected with the reason "nobody here rents rooms".
- **Why:** The fixtures for the turn pipeline need fixed values now. Catalogue v2 (step 5) is on hold while the transfer-action model is open.
- **Details:** [Design: the turn pipeline](design-turn-pipeline.md), §8

## 2026-10-12: Turn pipeline order and rules

- **Decision (Fredrik):** Every turn runs in this order: Jev intent, premise and inventory check, mechanics and state, NPCs, GM narration of confirmed outcomes. In addition: (1) a rejected action costs no game time; (2) catalogue v2 adds `give` now, and `eat` and `drink` come later; (3) `none_fits` uses no extra Grok call, and the GM handles it alone; (4) a prose/record mismatch is logged and counted as a bug that fails the fixtures, with no GM re-run; (5) the server strips injected text from the history and keeps no marked copy.
- **Why:** Six of seven playtest failures came from the pipeline order, not from the intent threshold (Case's analysis, 2026-10-12).
- **Approved (Fredrik, 2026-10-12 16:17):** The design document is approved at `4c1adae`. Work on the 7 migration PRs can start.
- **Details:** [Design: the turn pipeline](design-turn-pipeline.md)

## 2026-10-12: Jev reads player intent on all sessions; no intent LLM call

- **Decision (Fredrik):** `INTENT_JEV=on` for all new sessions on production and playtest. Jev reads the player's intent in one call. The Elixir heuristic is the fallback on a Jev error, a timeout or a missing key. We removed the Tier 1 intent LLM call (grok). The baseline variant stays the no-Jev arm, because the playtest series runs it. It now reads intent with the heuristic only.
- **Why:** Jev is fast and cheap and gives typed answers from free text (call-type rule, 2026-10-07). The Tier 1 call added time before the GM call (turn time p50 0.36 s, p95 1.9 s, latency study 2026-10-12). Supersedes the Tier 1 part of "GM pipeline direction" (2026-10-07).
- **Details:** [ex-tales-forge #193](https://github.com/whyse-ab/ex-tales-forge/pull/193), `TalesForge.IntentJev`

## 2026-10-12: Goals on the idea board

- **Decision:** The idea board shows goals at the top. Each card has zero or one goal. The north star ("first paying customer we don't personally know", Apr 2027) is a header line with its own countdown, not a goal. The goals are G2 to G7 from the roadmap, plus G7 "Our shared workspace (team tools)" with the target 2026-10-31. Founders vote on goals (a -1 needs a reason) and change the goal of a card. Bots and the QA session cannot change it. A month target uses the last day of the month.
- **Why:** The founders see which cards move which goal, how much is done and how much time is left.
- **Details:** [Founders' idea board, Goals](design-idea-board.md#goals)

## 2026-10-12: ElixirConf 2027 is not a project goal

- **Decision:** ElixirConf 2027 is not a project goal. It is a personal goal of Fredrik. We removed it from the roadmap.
- **Why:** The talk is personal. It is not a Tales Forge milestone.
- **Details:** [Roadmap 2027](roadmap-2027.md)

## 2026-10-12: Add animations to wiring section

- **Decision (fredrik@whyse.se, 2026-10-12, on the idea board):** build it. Add animations to the wiring section of the presentation
- **Why:** Plan: make section 4 "How it's wired" on /team/presentation move like the other sections already do. The five steps become a path from the idea board to production. A d20 token travels along the path. Each step lights up when the token reaches it, and the bot that does the step (Case, Bobby or Gentry) shows its portrait. The fast-lane step (admin and security fixes) branches off and skips the founder OK. After the path, the seven key facts appear one at a time. The animation starts when the section scrolls into view or when its slide opens in Present mode. A Replay button plays it again, as on every other animation. With reduced motion, the section shows the full, static picture. The page already has the parts for this: the TeamFlow hook (the d20 token on the change flow), data-reveal, and the data-motion rules in app.css. So the change stays in team_presentation_live.ex, team_hooks.js and app.css, with no new library. The text of the steps and facts stays the same. It must fit a 390 px phone and work in dark mode. Playtest gets it first. Verdict: feasible. Rough cost: S.
- **Link:** [the card on the idea board](https://tales-forge.fly.dev/team#idea-5448d20a-ebc6-4c36-bed6-56f37c57a66e)

<!-- board:idea:5448d20a-ebc6-4c36-bed6-56f37c57a66e -->

## 2026-10-12: Refine ideation process

- **Decision (fredrik@whyse.se, 2026-10-12, on the idea board):** build it. Add a chat box instead of current idea input, bot then checks for already existing cards or variants or if it already is implemented before it creates a new card. Otherwise it displays links to the similar card. Show a notification that a card is created
- **Why:** **Problem.** The New idea form on the board takes a title and a body. It does not check for cards that exist. Thus founders can add a duplicate card, or an idea that is already done. The form also gives no clear message when it creates a card.

**Goal.** A chat box replaces the New idea form. The founder writes the idea. The bot looks for similar cards and for done work. If it finds a match, it shows links to those cards. If it finds no match, it creates the card and shows a notification.

**Proposed approach.**
1. Replace the `board-add` form (`phx-submit="add"`) in `lib/ex_tales_forge_web/components/team_idea_board.ex` with a chat box. Keep the draft save (`data-draft="new-idea"`).
2. Add a module `TalesForge.Board.Similar` in `lib/ex_tales_forge/board/similar.ex`. It compares the new text with the title and body of each card. It returns the best matches with a score. Step one uses a text match in Postgres (`pg_trgm` similarity), so it adds no AI cost. A Done card counts as "already implemented".
3. The `add` event first calls `Similar.matches/1`. When the score is high, the chat box shows the matches as links to `Board.url/1`, with two buttons: "Open card" and "Create anyway". When there is no match, it calls `Board.create_idea/2` as today.
4. After `Board.create_idea/2` succeeds, show a flash notification with a link to the new card.
5. Add tests in `test/ex_tales_forge/board/similar_test.exs` and for the event in the board LiveView test.

**Acceptance criteria.**
- The board shows a chat box in place of the New idea form.
- A text that is close to an open card shows a link to that card. No card is created.
- A text that is close to a Done card shows the link and says that the work is done.
- "Create anyway" creates the card.
- A text with no match creates the card in Ideas.
- After each new card, the founder sees a notification with a link.
- Tests pass in CI.

**Size: M.**

**Risks.**
- The text match can miss an idea that uses other words. Mitigation: show the top three matches, and add an AI check later if needed.
- The text match can stop a good new idea. Mitigation: the "Create anyway" button.
- `pg_trgm` needs a migration. A migration is not on the admin list. Mitigation: ship the migration in one small normal-lane PR first, as the board design doc says.
- An AI check through `lib/ex_tales_forge/llm.ex` would change a file outside the admin list.

**Deploy lane: fast.** The main change is in `lib/ex_tales_forge/board/` and the board component, which are on the `[admin]` list in `.github/deploy-lanes.txt`. Only the `pg_trgm` migration takes the normal lane.

**Confidence.** High confidence: the board has all the data, and the form and `create_idea/2` exist. Verdict: feasible. Rough cost: M.
- **Link:** [the card on the idea board](https://tales-forge.fly.dev/team#idea-42fd5696-78dd-4551-bd7f-008ab7c37a76)

<!-- board:idea:42fd5696-78dd-4551-bd7f-008ab7c37a76 -->

## 2026-10-12: Archive for ideas

- **Decision (Fredrik, 2026-10-12):** the board gets an Archive. A founder archives a card in Ideas or Parked with a short reason; the card leaves the board and goes to the Archive panel, which a small tile next to Parked opens (a box icon and a count). The panel lists the archived cards newest first, with the Ideas tag filter and a search box, and shows who archived each card and when. Restore sends a card back to Ideas. Founders can delete an archived card for good (spam or duplicates) after they type its title; the delete removes the card's images and writes an audit record. Bots and the Gentry QA session cannot archive or delete.
- **Why:** spam, duplicates and old ideas made the Ideas lane and Parked long. The archive keeps them out of the way but keeps their votes, comments and history, so a founder can bring a card back. A hard delete is only for cards that must go, and it always leaves an audit record.
- **Link:** [Board states: Archive](design-board-states.md#archive)

## 2026-10-10: Tags and a newest/oldest toggle in the Ideas lane

- **Decision (Fredrik, 2026-10-10):** the Ideas lane sorts newest first or oldest first, with one icon toggle button. Top ranked and Most votes go out of the lane. Tags replace the Written by and Mentioning me filters: each card has an automatic founder tag (the author's display name), and founders add and remove free-text tags on the full card. A tag cloud above the lane filters the cards with AND logic. The URL holds the order and the selected tags (`?sort=`, `?tags=a,b`).
- **Why:** one toggle and one tag cloud are easier to use, also on a phone, than a bar with three controls. Tags let the founders group ideas by topic and by founder with one control. The "Pings for you" box already lists the cards that mention you.
- **Link:** [Board states: Tags in the Ideas lane](design-board-states.md#tags-in-the-ideas-lane), [PR #167](https://github.com/whyse-ab/ex-tales-forge/pull/167)

## 2026-10-10: Approve once

- **Decision (fredrik@whyse.se, 2026-10-10):** a founder's Approve on a PR is kept when the PR gets new commits. Bobby links the PR again with the new head sha; the card history notes "New commit <sha> after approval; approval kept", and the `pr.approved` merge uses the newest linked head. The founders answer again only when the link sets `player_change: true`, which means the new commit changes what the PR does for players. A link before any answer adds no second approval request.
- **Why:** small fixes after review (tests, wording, a rebase) do not change what players get, so one Approve is enough. This keeps the merge lane fast and keeps the founders' attention on changes that matter to players.
- **Link:** [Board states: PR approval in Building](design-board-states.md#pr-approval-in-building)

## 2026-10-10: Screen capture in chat

- **Decision (fredrik@whyse.se, 2026-10-10, on the idea board):** build it. Built-in screen capture in the team chat (of the app or screen, not the chat window itself).
- **Why:** Two parts, both built on one shared image store. 1) Images on cards and in team chat: paste, drag or pick a file (PNG/JPEG/WebP, max about 5 MB), stored once (Fly Tigris bucket or Postgres to start) and shown as thumbnails that open full size. 2) A 'Capture screen' button in chat and on cards that uses the browser's built-in screen sharing (getDisplayMedia) to grab one still of a tab, window or whole screen, then lets you add a note before posting. Bots read the image link through the chat and board APIs, so Bobby and Gentry can see exactly what looks wrong. Desktop browsers handle capture well; on phones we offer file upload only. Verdict: feasible, because the browser does the capture for us; the main work is one shared image store used by both chat and cards. Verdict: feasible. Rough cost: M.
- **Link:** [the card on the idea board](https://tales-forge.fly.dev/team#idea-b96b9f95-bf82-466e-b700-418dc33d8130)

<!-- board:idea:b96b9f95-bf82-466e-b700-418dc33d8130 -->

## 2026-10-10: Code heat map

- **Decision (fredrik@whyse.se, 2026-10-10, on the idea board):** build it. Show the code tree by intensity: most calls, most total time, highest average time. Filter it and highlight hot spots.
- **Why:** Plan: the BEAM can count calls and time per function with built-in call-time tracing (no new library). An admin page under Operate shows the code tree (app, module, function) as a heat map, colored by one chosen measure: number of calls, total time, or average time per call. You can filter by module name and by minimum value, and the hottest spots get a highlight. To keep prod safe, measuring runs only in short windows a founder starts (for example 60 seconds), only for our own modules, and stops by itself. Results are saved, so the page can show the last runs and a rolling 7-day view. Playtest gets it first. The tracing and the tree building live in one module; the page only renders. Verdict: feasible with caveats. Rough cost: M.
- **Link:** [the card on the idea board](https://tales-forge.fly.dev/team#idea-989f1dc5-a732-450d-a3ee-c12b112f02ed)

<!-- board:idea:989f1dc5-a732-450d-a3ee-c12b112f02ed -->

## 2026-10-10: update presentation after shared workarea

- **Decision (fredrik@whyse.se, 2026-10-10, on the idea board):** build it. the new shared work area is now live and several founder are now contributing to the game - presentation needs to reflect this
- **Why:** The presentation (/team/presentation) still describes the shared work area as coming. Section 6 "One shared board" is a mock, and the module doc says "the shared board that is coming". Section 7 still sends ideas to docs/future-ideas.md or to Case. The plan: (1) Replace the section 6 mock with the live board: real columns and card counts from TalesForge.Board, with a link to /team#idea-board. (2) Show who contributes: founders who added, voted on or commented on cards, with live counts since inception (7 Oct 2026) or a rolling 7-day window, by the chart rule. (3) Rewrite section 7 so the board is the first way to take part, and keep future-ideas.md as the archive. (4) Mention team chat and the Founders/Bots online counter when they are live. (5) Update the moduledoc and the anchors in one place. All founders are shown equally, with an inclusive "together" tone. Verdict: feasible. Rough cost: M.
- **Link:** [the card on the idea board](https://tales-forge.fly.dev/team#idea-8018439a-33c4-4950-a64c-0c99ca02fba3)

<!-- board:idea:8018439a-33c4-4950-a64c-0c99ca02fba3 -->

## 2026-10-10: Sorting button for Ideas

- **Decision (fredrik@whyse.se, 2026-10-10, on the idea board):** build it. Sorting button for Ideas. Possibility to filter on Ideas a specific user has written, for example Fredrik, Håkan, Filter on Ideas I'm mentioned in, in the comment section. Sort on newest or oldest.
- **Why:** Good idea, and it fits the board well. A small sort-and-filter bar above the Ideas column, with three controls: (1) Sort: Most support (today's order, net votes then total votes, stays the default), Newest, Oldest. (2) Written by: a founder picker (Fredrik, Jeanette, Thobias, Håkan, Max). (3) Mentioning me: shows only cards where someone @mentioned you in a comment. The board already stores each card's author, its created time and the @mentions in comments, so we need no new data. Everything stays in the board's one place for ranking (TalesForge.Board), and the choices go in the page URL so a filtered view can be shared as a link. Built with daisyUI like the rest of the board, with tests for each sort and filter. Verdict: feasible. Rough cost: S.
- **Link:** [the card on the idea board](https://tales-forge.fly.dev/team#idea-b18fc8dc-97bb-4fda-a7fa-d90e47e94480)

<!-- board:idea:b18fc8dc-97bb-4fda-a7fa-d90e47e94480 -->

## 2026-10-10: In game, scroll so the last text is visible

- **Decision (hawkan.fredriksson@gmail.com, 2026-10-10, on the idea board):** build it. When I play the game now, I write what I want to do, and GM answer but I need to scroll manually to read the text. It should always scroll automatically and show the latest text. If I want to read older text I have to scroll back manually instead. Autoscroll forward when a new text appear.
- **Why:** Good catch, Håkan. Today the Story panel stays where it is when the GM answers, so you have to scroll down yourself. The fix is a small browser hook on the Story panel: when a new GM text or your own action appears, the panel scrolls to the bottom. If you have scrolled up to read older text, it stays where you are and shows a small "New text ↓" button instead, so reading back is never interrupted. The same applies when the GM is thinking and when a scene loads. This touches only the play page (the Story panel and one small JavaScript hook), with a test for the hook behaviour. No game logic and no AI calls change. Verdict: feasible. Rough cost: S.
- **Link:** [the card on the idea board](https://tales-forge.fly.dev/team#idea-6d08cf7e-43ad-42d9-a050-c6ba1a10a3e8)

<!-- board:idea:6d08cf7e-43ad-42d9-a050-c6ba1a10a3e8 -->

## 2026-10-10: /team opens with "Our workspace"

- **Decision (Fredrik, 2026-10-10):** the /team landing page opens with a compact workspace header: "Our workspace", "Ideas, building and chat for the whole crew", and four quick stats as links to the board (ideas waiting for votes, Founder check cards for you, PRs waiting for approval, pings for you). The hero "How Tales Forge gets built" with the starting-point banner and the crew picture is on /team/presentation only.
- **Why:** /team is the place where the crew works every day. The stats show at once what needs you. Every founder can approve, so the header names no role.
- **Link:** [ex-tales-forge #150](https://github.com/whyse-ab/ex-tales-forge/pull/150), [team page content](team-page/content.md#landing-page-team-our-workspace)

## 2026-10-10: Writing in the comment field in cards

- **Decision (fredrik@whyse.se, 2026-10-10, on the idea board):** build it. Only one person at a time can write a comment in a card. It must show the other users/founders that someone is writing a comment so we don't write at the same time and we lose information
- **Why:** When a founder starts writing in a card's comment box, everyone else with that card open sees a line under the box like "Fredrik is typing…". It goes away a few seconds after they stop or when they post. We build it on the live presence we already use for the Founders/Bots online counter, so the only new part is a small 'typing' signal per card. No hard lock: the box stays open for everyone, so nobody gets blocked by a forgotten tab, and comments are saved one by one, so nothing gets overwritten. The same signal can later show on the per-question answer boxes too. Verdict: feasible. Rough cost: S.
- **Link:** [the card on the idea board](https://tales-forge.fly.dev/team#idea-9615a9bd-213b-4a25-bcca-434b962e58d5)

<!-- board:idea:9615a9bd-213b-4a25-bcca-434b962e58d5 -->

## 2026-10-10: Team chat with mentions

- **Decision (fredrik@whyse.se, 2026-10-10, on the idea board):** build it. Chat with anyone on the team, with mentions like @Case, @fpahlen and @founders.
- **Why:** A chat panel on /team for founders and bots. It fits what we already have: Phoenix PubSub and Presence (already used for "Online now") give live messages, and the board already reads @case, @bobby and @gentry in comments and wakes that bot. Chat uses that same mention reader and the same bot wake-up, so there is one place for mentions. Messages are kept in the database (a new chat_messages table) so history stays after a reload. @fpahlen and other GitHub handles come from the whyse-ab/tales-forge team; @founders means all of them. A mention gives a highlight and an unread badge on /team. Admin-only, so it goes in the fast lane. Verdict in one line: the live chat is simple with what we have; the caveats are bot wake-up cost and any notice outside the site. Verdict: feasible with caveats. Rough cost: M.
- **Design (Bobby, built in [ex-tales-forge #145](https://github.com/whyse-ab/ex-tales-forge/pull/145), normal lane, waiting for a founder's Approve):**
  - One shared room, in a panel that opens from the header next to the who-is-online counter. The Chat button on a person opens the room with their `@handle`.
  - Mentions use the board's one parser (`TalesForge.Board.Mentions`, from #142).
  - A founder mention gives an unread badge on the Chat button. There is no email or push.
  - Only a founder's mention wakes a bot. The wake-up is a `chat.mention` job in the board's webhook outbox, with the last 10 messages and a reply URL. Bots reply through `/internal/chat` with their board tokens.
  - The chat lives on production only, like the board. On playtest the Chat buttons link to production.
  - Messages are kept in `team_chat_messages` with their mentions. Retention is the deferred question.
  - The shared header loads the admin chat code through config, so admin and shared code stay separate.
- **Link:** [the card on the idea board](https://tales-forge.fly.dev/team#idea-9fb3b555-6144-46a3-81d0-35a6c0cba9a0)

<!-- board:idea:9fb3b555-6144-46a3-81d0-35a6c0cba9a0 -->

## 2026-10-10: Chatt/Comment ping others

- **Decision (hawkan.fredriksson@gmail.com, 2026-10-10, on the idea board):** build it. To be able to ping somebody and have a discussion in a card.
- **Why:** Today a comment can wake the bots with @case, @bobby or @gentry. This idea makes the same work for founders: write @fredrik, @jeanette, @thobias, @hakan or @max in a card comment and that person gets a ping. The comment box suggests names as you type, the name shows highlighted in the comment, and the person sees a small badge on /team with the cards that ping them until they open the card. It builds on the mention code we already have (one place for mentions, so bots and founders share it), plus a small table of unread pings. Verdict why: the bot mentions already work, so we extend them to founders. Verdict: feasible. Rough cost: M.
- **Link:** [the card on the idea board](https://tales-forge.fly.dev/team#idea-3acb46bc-742a-48bc-b54b-1fc9477ddb9e)

<!-- board:idea:3acb46bc-742a-48bc-b54b-1fc9477ddb9e -->

## 2026-10-10: Admin split: one home for each page, production or playtest

- **Decision (Fredrik, via Case, 11:36):** the admin plan in `/workspace/admin-split/plan.md` (Case's analysis) is approved. Each page has one home:
  - **Production only:** the idea board and `/team`, `/team/presentation`, founders' decisions, the docs (and surveys, as before). Playtest redirects these to production.
  - **Playtest only:** playtest runs (as before).
  - **Both, per app:** sessions, NPCs, turns, costs (prod has the total), telemetry, logs, code docs, the game.
- **Build order:** (1) AppRole areas and redirects, and nav items marked by home (normal lane). (2) An environment badge in the admin layout, and shared "lives on production" and "same page on the other app" links (normal lane). (3) After 1 and 2 are on production: costs cross links, menu dedupe, presentation live-stat labels, Jev latency under Operate (fast lane). (4) Later: a playtest-stats peer endpoint for the presentation.
- **Why:** both apps showed the same pages, some of them empty or with data from the wrong app. One home for each page removes the duplicates and the empty board slot on playtest. The badge shows which app you are on.
- Fredrik pre-approved the normal-lane merges and production deploys for this plan.
- **Status:** steps 1 to 3 are on both apps. [#135](https://github.com/whyse-ab/ex-tales-forge/pull/135) (712eca8, normal lane), [#136](https://github.com/whyse-ab/ex-tales-forge/pull/136) (1508e23, normal lane), [#137](https://github.com/whyse-ab/ex-tales-forge/pull/137) (311b627, fast lane), [#138](https://github.com/whyse-ab/ex-tales-forge/pull/138) (7d6d8c9, fast lane). Production v119 and playtest v124 run 7d6d8c9. Step 4 (playtest-stats peer) is for later.

## 2026-10-10: Who's online right now

- **Decision (fredrik@whyse.se, 2026-10-10, on the idea board):** build it. Use Phoenix Presence to show which founders and bots are online and what each is doing right now.
- **Why:** A small "Online now" strip on /team that shows who is here right now: founder avatars light up while their /team or /admin page is open, with a short note on what each person is looking at (for example "Idea board" or "Playtest runs"). We build it with Phoenix Presence on the PubSub we already run, in one module (TalesForgeWeb.Presence) that every founder LiveView joins through one on_mount hook, so the logic lives in one place. Bots (Case, Bobby, Gentry) do not keep a page open, so they show as online when they made a board API call or ran a job in the last few minutes, with that call as their "doing now". It is admin-only, no game-engine change, so it goes in the fast lane. Tests cover join, leave and the bot activity window; docs and doctests follow our standard. Verdict: feasible. Rough cost: S.
- **Built (2026-10-10):** [ex-tales-forge #139](https://github.com/whyse-ab/ex-tales-forge/pull/139), cda4ed5, normal lane (new `GET /internal/online` endpoint). One list for both apps: production reads playtest's founders from that endpoint every 10 s with `COSTS_PEER_TOKEN` and keeps them for 30 s. This is the same pull model as the costs page, so playtest needs no data about production. Bots show their latest board action, board API call or pull request, with the last-seen time. Production v120 and playtest v125 run cda4ed5. Auto-Done moved the card to Done.
- **Header (2026-10-10, Fredrik via Case):** who is online moved to the header of every admin page and /team: a counter "Founders: 2 Bots: 2" (bots active in the last 10 minutes) that opens a list with avatar, name, page or latest activity, and a disabled "Chat" placeholder ("Coming with team chat", config `:team_chat_placeholder`). The /team "Online now" section is removed, because the header shows the same data. [ex-tales-forge #141](https://github.com/whyse-ab/ex-tales-forge/pull/141), 95e26be, normal lane. Production v124 and playtest v127 run 95e26be.
- **Link:** [the card on the idea board](https://tales-forge.fly.dev/team#idea-5c55bf37-8c6d-479b-a019-5466c66d0efd)

<!-- board:idea:5c55bf37-8c6d-479b-a019-5466c66d0efd -->

## 2026-10-10: Founder pages are up to date; the five founders are equals

- **Decision (Fredrik, board card "check that founder page is up to date", moved to Building 10:08):** Max is a founder like the others. "Apprentice" was an internal joke, so no founder has a title. This replaces the 2026-10-09 wording "our vibe-coding founder and RPG apprentice" and "never played a tabletop RPG".
- **Status:** [ex-tales-forge #131](https://github.com/whyse-ab/ex-tales-forge/pull/131) merged as ca1cfca (fast lane). It is on playtest v117 and prod v112. The card is Done.
  - Gentry's old drawn SVG avatar is gone. The bots' small avatars use the Grok Imagine portraits.
  - The change flow starts on the idea board and shows both deploy lanes. The board section says it is live and follows [design-board-states.md](design-board-states.md). The learning rule text says it is live (physical skills right away, at most +1 for each long rest; other skills during sleep; reflection from level 10). Release numbers that go stale are removed.
  - `docs/team-page/content.md` and `data.json` match the app.

## 2026-10-10: Positive-framing cleanup merged (ex-tales-forge #122)

- OK'd by Fredrik (08:01). ex-tales-forge PR [#122](https://github.com/whyse-ab/ex-tales-forge/pull/122) merged as `6f1b383` after main was merged in (vote fix #124). Test and Dialyzer passed.
- The PR adds the language rule to `CONTRIBUTING.md` and `AGENTS.md`. Playtest pages show "4.21/5 · confident 70%" and "N low-confidence". The team pages show the confident share.
- Prompts did not change. The GM golden test is the same. The identifier renames (`unsure_share`, `unsure_below`, `unsure_pct` and others) wait for a later normal-lane PR.
- Lane: normal. "Deploy to production" ran for `6f1b383` (06:05 UTC) and then for main's tip `6ec8e31` (#125, 06:11 UTC). Both runs were started by the other workstream. Now playtest v111 and production v104 both run `6ec8e31`, which includes #122.

## 2026-10-10: "Fredrik is typing…" on a card's comment box

- **Decision (Håkan's card "Writing in the comment field in cards", Fredrik's answers, moved to Building 15:27):** when a founder writes a comment on a card, the others see "<name> is typing…" under the comment box and a small pencil on the thin card. It is a hint, not a lock.
- **Design choices:** Phoenix Presence tracks the writer under their own LiveView (`TalesForge.Board.Typing`), so a closed tab removes the hint. The hint goes when the founder posts, closes the card, or stops for 5 seconds. Only the start and the stop update the board, not each keystroke. Built: [ex-tales-forge #152](https://github.com/whyse-ab/ex-tales-forge/pull/152), ef07ee6, admin lane.

## 2026-10-10: A PR waits for approval in Building

- **Decision (Fredrik, via Case, 15:08; built in [#149](https://github.com/whyse-ab/ex-tales-forge/pull/149), 795c24b, normal lane):** a card with a normal-lane PR that waits for an OK stays in Building with a "PR waiting for approval" badge. Founders Approve or Request changes on the full card and on the thin card. Approve wakes Bobby (`pr.approved`) to merge and ship. Request changes wakes him with the comment. Founder check is only for the refined idea. A data migration moves the cards that are in Founder check because of a PR back to Building.
- **Why:** a card that went back to Founder check for a PR looked like a new idea to decide on. The badge keeps the card where the work is.

## 2026-10-10: Answer boxes save together with the move

- **Decision (Fredrik, via Case, 15:00; built in [#144](https://github.com/whyse-ab/ex-tales-forge/pull/144), f3fba8d, admin lane):** no answer button for each question. Each open question has a text box and a Defer toggle (Defer disables the box). The boxes save together when the card moves or closes, and on blur. The gate uses the boxes on the screen; the server checks it again.
- **Why:** one button for each question was many clicks. Founders answer and then move the card.

## 2026-10-10: Founders ping each other with @mentions on the board

- **Decision (Håkan, board card "Chatt/Comment ping others", moved to Building 14:54; Fredrik: no email):** a board comment that names a founder (`@fredrik`, `@thobias`, `@hakan`, `@jeanette`, `@max`) or `@founders` pings that founder. The ping shows under "Pings for you" on the /team board until the founder opens the card. Only the founders named get a ping, not everyone who commented (Håkan's answer). There is no email for now (Fredrik's answer).
- **Design choices:** one parser for bot and founder mentions (`TalesForge.Board.Mentions`). A handle is the founder's first name from the team data, in lower case and without accents (`@håkan` also works). Founders sign in with GitHub, so the board finds the handle from the session's GitHub login (`:board_founder_handles`: fpahlen, jpa71, tsjokvist, Hawkan-Fredriksson, maxpahlen; case-insensitive; follow-up #143). The author gets no ping for their own mention. Pings live in a new table, `board_pings`, so the PR takes the normal lane. The ping list is on the /team board, not in the shared header, so the header work for presence stays separate. The comment box suggests names as you type (arrow keys and Enter, or a click), and mentions show highlighted. This is separate from the larger "Team chat with mentions" card, which can reuse the parser.
- **Status:** [ex-tales-forge #142](https://github.com/whyse-ab/ex-tales-forge/pull/142), normal lane, waiting for a founder's Approve on the card.

## 2026-10-10: An answer box for each open question

- **Decision (Fredrik, via Case, 14:37):** the full card shows each open question from Case's refinement with its own answer box and a Defer toggle, in every column. The board keeps each answer with who and when. A founder can change their own answer. Founder check → Building needs every question answered or deferred, and needs no comment. Each answer or deferral goes in the move log and wakes Case (`question.answered`) when the card is in Refining.
- **Why:** one comment for all questions was hard to read and hard to check. One answer for each question makes the gate clear, and Case gets the answers while refining.
- **Built (2026-10-10):** [ex-tales-forge #140](https://github.com/whyse-ab/ex-tales-forge/pull/140), b0c52ca, normal lane (new table `board_answers`). Production v123 and playtest v126 run b0c52ca. Details: [design-board-states.md](design-board-states.md#open-questions).

## 2026-10-10: The board moves cards to Done automatically

- **Decision (Fredrik, 2026-10-10, via Case):** after each production boot, the board moves a card from Building to Done as `bot:board` when the merge commit of its linked PR is in the running prod release. The move note names the release. When GitHub does not answer, the board tries again later. Bobby's manual move stays as the fallback.
- **Why:** Done then means "on prod" with no manual step.
- **Link:** [design-board-states.md](design-board-states.md#automatic-done), ex-tales-forge#132.

## 2026-10-10: Idea board: step-named move buttons, links by bots only

- **Decision (Fredrik, 2026-10-10, via Case):** each move button has the name of its target step ("Send to Founder check", "Start building", "Put on hold"). The names come from `TalesForge.Board.Transitions`. Only bots add links (the PR, the playtest run). The card shows each PR with its number, title and status (open, merged, on prod), and a thin card shows a small PR badge.
- **Why:** buttons that say what happens, and links that are always correct.
- **Link:** [design-board-states.md](design-board-states.md), ex-tales-forge#130.

## 2026-10-10: Idea board full card: move buttons, downvote reasons, Done gate

- **Decision (Fredrik, 2026-10-10, via Case):** the full card has Back, Forward and On hold buttons from `TalesForge.Board.Transitions` instead of a "Move to" list. A failed gate disables a button and shows the reason. A downvote needs a reason, which shows next to "Needs work". Case's refinement is read-only, with an Edit button. Building → Done needs the PR's merge commit in the running prod release. Case confirmed the readings of the state machine; `pr.link_added` stays removed and `pr.changes_requested` stays.
- **Why:** clear next steps on each card, and a "needs work" signal that says what needs work.
- **Link:** [design-board-states.md](design-board-states.md), ex-tales-forge#128.

## 2026-10-10: Idea board card state machine, vote gates and thin cards

- **Decision (Fredrik, 2026-10-10, via Case):** the board follows [design-board-states.md](design-board-states.md). One pure module (`TalesForge.Board.Transitions`) checks every move on the server and tells the UI which moves are possible and why. Ideas → Refining needs at least 1 upvote and 0 downvotes. Votes only set the backlog order (net votes, then total votes) and do not wake bots: `idea.pullable` is removed. Only moves and @mentions wake bots. A card with no votes is faded, and a card with a downvote has a "needs work" border. A card that cannot move shows the reason. Every card is thin, with the vote buttons inside the card. No WIP limit.
- **Why:** votes started refinement by accident; one rule table for server and UI.
- **Link:** [ex-tales-forge#126](https://github.com/whyse-ab/ex-tales-forge/pull/126), and the thin-cards follow-up PR.

## 2026-10-10: Merge approvals move onto the idea board

- **Decision (Fredrik, 2026-10-10, via Case):** a normal-lane PR waits for a founder's OK on its board card, not in chat. Bobby posts the PR to the card (`POST /internal/board/prs`: PR link, head sha, one line on what changes for players); the card goes to Founder check; a founder presses Approve or Request changes (with a comment). The board records who, when, which PR and its head sha, shows the approval log on the card and in its history, and wakes Bobby with `pr.approved` / `pr.changes_requested`. Fast-lane PRs need no OK.
- **Why:** one place for the founders' OK, with an audit trail tied to the exact commit approved.
- **Link:** [ex-tales-forge#125](https://github.com/whyse-ab/ex-tales-forge/pull/125), [idea board design note](design-idea-board.md).

## 2026-10-10: Live numbers everywhere on /team/presentation, data.json as a labelled fallback per group

**Decision:** Every number on the founders' presentation that has a live source now reads it; `priv/team/data.json` is only the fallback, chosen per number group (never per number) and labelled "as of <date>". Timelines say their window. Shipped as ex-tales-forge PR [#114](https://github.com/whyse-ab/ex-tales-forge/pull/114) (merged `6afdb4a`, playtest v101).

- **Live from GitHub:** PRs and commits (the PR feed, as before); tests, doctests, failures and coverage from the "Test" job log of main's latest successful CI run (`GITHUB_FEED_TOKEN`, Actions: read); the decision count and per-day count from this file on GitHub (`GITHUB_DOCS_TOKEN`, ETag). Refreshed by the PR feed poller at most every 10 minutes (`TalesForge.PrFeed.Extras`). Checked on playtest after deploy: 1,141 tests + 184 doctests, 0 failing, 87.42% coverage at `6afdb4a`; 98 decisions.
- **Live from the app's own database** (`TalesForgeWeb.TeamLiveNumbers`): AI spend per day (last 7 days, same rows as the costs page), Jev intent latency p50/p95/max (last 7 days), Jev score per persona over runs started since 2026-10-07 (playtest; production has no playtest runs, so it shows the last batch labelled "as of").
- **No live source, labelled "as of":** the eval set, the shadow test, per-batch spend and the batch series (one-off analyses).
- **Windows:** PRs, commits and decisions per day "since 2026-10-07" (earlier days as a chip or count); spend and latency "last 7 days".
- **Lane:** all six files are on the admin list, but the deploy-lane check came out **normal** because main also carries the other workstream's undeployed normal-lane #113 (idea board foundation, with a migration). So production was **not** deployed from here: it stays on v95 (`f7f3abd`) and gets this change with the next "Deploy to production", which is #113's owner's call.

## 2026-10-10: /team Replay buttons fixed (#112)

- **Decision (Fredrik, via Case, ~04:45; admin-only, fast lane, merge when green):** fix the /team/presentation Replay buttons, which were reported as not working.
- **Cause:** I reproduced it in headless Chrome at 390 and 1280 px with a live feed snapshot every 2 s. Each LiveView patch from the live PR feed reset the page root's `data-motion` to the server's "auto". The animations only run under "full", so Replay changed state but nothing moved. Revealed sections also lost `is-visible`.
- **Fix:** the TeamPage hook's `updated()` restores both after every patch. In the same browser run, flow, lanes and board now visibly replay at both widths.
- **Status:** #112 merged as f7f3abd (fast lane). It is on playtest v99 and prod v95.
- **Next, from the same request:** every number on the presentation should be live where we have a source, with "as of <date>" per number group, and the charts labelled "since 2026-10-07" or "last 7 days". That work is not started yet.

## 2026-10-10: Idea board: the eight open questions answered

- **Decision (Fredrik, 2026-10-10, via Case):** any one founder may OK a card (drag to Building), but not while any founder has a -1 vote on it; Case pulls ideas on its own at score > 0.3 and top 3, and founders can also move cards to Refining; decay stays (0.8, +2 days); the board lives and is editable on /team; production only, playtest links across; decisions.md commits use a GitHub App, not a personal token; open Collab items are imported as Ideas and /admin/decisions becomes read-only; Bobby moves Building to Done after Gentry's check.
- **Why:** unblocks the build of the board with a single, safe approval rule and no personal tokens.
- **Link:** [Founders' idea board design note, Resolved](design-idea-board.md#resolved-fredrik-2026-10-10-via-case).

## 2026-10-10: Start the founders' idea board, design note first

- **Decision (Fredrik, 2026-10-10):** start the founders' idea board, the working version of "One shared board" on /team: founders add and vote on ideas, Case refines, a founder drags a card to Building as the OK (which writes its own entry here), Bobby builds, then Done. Design note first; no code until Fredrik has answered its open questions.
- **Why:** turns the Collab decision queue into an idea-to-done flow where every founder can steer the bots and give the OK, and keeps the board and this log in step.
- **Link:** [Founders' idea board design note](design-idea-board.md).

## 2026-10-10: Free hands overnight to reorganise the admin area

- **Decision (Fredrik, via Case, 2026-10-09 ~21:54, before bed):** the bots may reorganise the whole admin area of ex-tales-forge tonight, and merge and ship it (playtest and production) without waiting for his OK, because every change can be reverted.
  - Scope: inventory every admin route and nav item on both apps, regroup them by purpose (Founders, Play and test, Operate, Develop, Docs), add an admin home with one card per section, and move old or unused pages to an Archive. A page is removed only when it is clearly dead.
  - Every old URL keeps working (redirects, with tests), and the pages fit a 390 px phone.
  - The one-place rule holds: surveys live on production, playtest runs on playtest, and the other app links across.
  - Fast lane where possible: admin-list files in one PR. Router and shared CSS, JS and layout changes go in a separate normal-lane PR, followed by the manual "Deploy to production" once playtest is verified.
- **Why:** the admin pages grew one at a time and are hard to find; Fredrik wants them organised by purpose.
- **Status:** shipped 2026-10-10 ~04:45.
  - **#110** (855695e, normal lane): router, grouped nav, and the new admin home (`TalesForgeWeb.AdminSections`). Moved URLs redirect with a 302 after sign-in (`TalesForge.AdminPaths`):
    - `/admin/sessions` → `/admin/play/sessions`
    - `/admin/playtest` → `/admin/play/runs`
    - `/admin/survey(s)` → `/admin/founders/survey(s)`
    - `/admin/decisions` → `/admin/founders/decisions`
    - `/admin/costs` → `/admin/operate/costs`
    - `/admin/oban` → `/admin/operate/telemetry`
    - `/admin/npc-definitions` → `/admin/archive/npc-definitions`
  - Cross-app links keep the old paths so that they work with any version of either app.
  - #110 went to playtest v97, then a manual "Deploy to production" put it on prod v93.
  - **#111** (999740b, admin fast lane): the admin-list pages link to the new paths and name their section. It went to playtest v98 and prod v94.
  - Nothing was removed: NPC definitions is still in use, so it moved to the Archive.

## 2026-10-09: Hover cards on the call-type rule; replay buttons always visible (first fast-lane deploy)

- **Decision (Fredrik, OK via Case, ~19:56 and ~20:01; admin-only, fast lane):** on `/team/presentation`, each of the three call types in "The call-type rule: one turn, three call types" gets a hover card (tap to open on phones):
  - **Elixir:** a short, simplified version of the real roll-under check (`Game.Mechanics`: effective level, d20, success / partial success / failure), highlighted on the server.
  - **Jev:** the player's words plus a little context (where they are, who is nearby) in; the typed intent out as JSON (`speak`, `brenna`, `persuasion`, `now`, 0.92, `benign`).
  - **GM (LLM):** the typed turn result in, prose out.
  - The cards are keyboard-accessible (focus opens a card, Esc closes it, `aria-expanded` and `aria-describedby`), simply appear with reduced motion, and fit a 390 px phone.
  - The Replay button on every animation (change flow, three lanes, mock board) is now always visible, including with reduced motion, and has an `aria-label`. With reduced motion it shows the whole, static diagram.
- **Why:** founders who don't code can see what each call type actually takes in and gives back. The Replay button was hidden until an animation had played and never showed with reduced motion.
- **Status:** merged 2026-10-09 ([#109](https://github.com/whyse-ab/ex-tales-forge/pull/109), main `3cebbab`). This was the first merge on the admin fast lane ([decision above](#2026-10-09-a-fast-deploy-lane-for-admin-work)): the Deploy lane job said **admin** (6 files, all on the admin list, both in this merge and since production), and the merge deployed to playtest (release v96) and production (release v92) with no manual step. Both run `3cebbab` and pass their health check; `deployed/production` moved to `3cebbab`. Only changes to files on `.github/deploy-lanes.txt` `[admin]`; styles are Tailwind classes in the team components, with no shared CSS or JS.
- **Details:** [ex-tales-forge PR #109](https://github.com/whyse-ab/ex-tales-forge/pull/109) (`TalesForgeWeb.TeamPeek`).

## 2026-10-09: One source for the team page's pace numbers: live from GitHub, data.json only as a fallback

- **Decision (Fredrik, OK relayed by Case, ~17:55):** the pace numbers on `/team/presentation` come from one place. That covers pull requests (total, merged, open, closed unmerged), PRs per day, and the commits on main (total and per day).
  - The headline stats and section 5 ("Pace and cost") both call the same function, `TalesForge.TeamPace.current/0`, so they can't disagree. The `/team` landing page shows none of these numbers.
  - **Live:** the live PR feed now reads GitHub's full lists (every pull request, every commit on main, page by page with ETags) and counts them. The page updates on every feed poll, about once a minute.
  - **Fallback:** [`team-page/data.json`](team-page/data.json)'s `pace` block, used only when the feed has no full count (no token, GitHub down, not polled yet, a list cut short). The page then labels the numbers "as of <date>"; live numbers read "live from GitHub". Live or fallback is decided for all of these numbers together, never per number.
  - Every other number on the page (tests, decisions, costs, playtests) still comes from `data.json`.
- **Why:** the headline and section 5 showed different numbers. One source of truth, live where possible, with an honest date when it isn't.
- **Status:** merged 2026-10-09 ([#108](https://github.com/whyse-ab/ex-tales-forge/pull/108), main `8a61175`), live on playtest (release v95, health check passing). There the numbers read live: 108 PRs, 106 merged, 0 open, 2 closed unmerged, 271 commits on main. The deploy lane was normal (the PR also edits `.github/deploy-lanes.txt` to add `team_pace.ex` to `[admin]`), so production was not deployed; it needs Fredrik's OK and the manual "Deploy to production" workflow.
- **Details:** [ex-tales-forge PR #108](https://github.com/whyse-ab/ex-tales-forge/pull/108) (`TalesForge.TeamPace`, `TalesForge.PrFeed.Pace`).

## 2026-10-09: Live PR feed on the /team landing page

- **Decision (Fredrik, OK 16:51):** merge ex-tales-forge [#102](https://github.com/whyse-ab/ex-tales-forge/pull/102), the live "what we're shipping" feed: the latest pull requests in the game's repo, CI while open, and whether each merge is on playtest or in production, polled from GitHub by the server every 60 s (browsers never call GitHub).
  - Since #105 split `/team`, the feed sits on the landing page right after the crew cards (section `#live`, "Live" in the page nav), in the slot left for it; the full presentation at `/team/presentation` is unchanged.
  - Needs `GITHUB_FEED_TOKEN` (read-only, only `whyse-ab/ex-tales-forge`); set on both apps with the same value, checked by name and digest only ([Fly secrets](fly-secrets.md)). Without it the section says "Live feed unavailable" and the rest of the page works.
- **Why:** founders see what the bots are shipping without opening GitHub.
- **Status:** merged 2026-10-09 ([#102](https://github.com/whyse-ab/ex-tales-forge/pull/102), main `eec7ddf`), live on playtest (release v93, health check passing, feed status ok with 15 pull requests, no GitHub errors in the logs). "On prod" reads "unknown" until production runs a release with #102 (it answers the feed's `GET /internal/version`). Production pending: it needs Fredrik's OK and the manual "Deploy to production" workflow.
- **Details:** [ex-tales-forge PR #102](https://github.com/whyse-ab/ex-tales-forge/pull/102) (`TalesForge.PrFeed`, `TalesForgeWeb.TeamPrFeedLive`).

## 2026-10-09: A fast deploy lane for admin work

- **Decision (Fredrik, via Case):** admin work gets a fast deploy lane. A merge whose changed files are **all** on an explicit admin list (the survey, costs, playtest admin and `/team` pages: modules, templates, `priv` data and tests) deploys to **playtest and production automatically**, without the Gentry/batch gate and without a prod OK. Production still goes through the same "Verify commit" job (sha on `main`, `Test` and `Dialyzer` green) and the tip-of-main guard. Anything that touches game engine code (`Game.*`, intent, world, NPCs, rules, packs) or shared parts (sign-in, Repo and migrations, config, `AICalls`, `mix.exs`/deps, CI) keeps the normal flow: playtest only, production by hand after Fredrik's OK. A mixed PR counts as a game change, and anything not on the admin list defaults to the normal lane. This refines "Deploy order: playtest first, then production" below.
  - **One list:** `.github/deploy-lanes.txt` in ex-tales-forge (`[admin]`). The router, the shared `app.css`/`app.js`, config, migrations, CI and the list itself are not on it, so a `/team` PR that also adds a route or shared CSS is normal (as #105, #102 and #101 would have been; #106 and #99 would have been admin).
  - **Production must not get unapproved game code:** the lane is admin only when the merge **and** every file changed since the commit production runs (tag `deployed/production`, moved by every production deploy) are on the list.
  - The lane, and the files that decided it, are written to the "Deploy to playtest" run summary.
  - **Boundary:** game code (and other shared code, except the router and the application that mount admin modules) must never depend on admin modules; CI checks it (`mix deploy.check_boundaries`).
  - **Gates:** admin code gets lighter gates: format and tests, no Credo, so no `@spec`/`@doc` demands. Game and shared code keep full rigor (Credo strict, specs, Dialyzer). `Test` and `Dialyzer` stay the required checks.
- **Why:** admin pages (surveys, costs, playtest reports, the founders' pages) don't touch the game. Waiting for Gentry, a playtest batch and a prod OK slows down work that can't change how the game plays, while game changes keep the full check.
- **Status:** merged 2026-10-09 with Fredrik's OK ([#107](https://github.com/whyse-ab/ex-tales-forge/pull/107), main `2f1c909`); live on playtest (release v94, health check passing). #107 itself took the normal lane (CI and shared files), so production was not deployed. Every merge stays normal until the next production deploy through the workflow sets the `deployed/production` tag; that deploy needs Fredrik's OK.
- **Details:** [Environments](environments.md#deploy-lanes-admin-work-goes-straight-to-production), ex-tales-forge `docs/DEPLOY-FLY.md`, [#107](https://github.com/whyse-ab/ex-tales-forge/pull/107).

## 2026-10-09: Max is a founder: our vibe-coding founder and RPG apprentice

- **Decision (Fredrik, ~16:23):** Max is one of the founders, our **vibe-coding founder**. He is also an **RPG apprentice**, in the sense that he has never played a tabletop RPG. The team page stops calling him "Max the apprentice" next to "the four founders": we are five founders (Fredrik, Thobias, Håkan, Jeanette and Max).
  - Copy: "We're five: Fredrik, Thobias, Håkan, Jeanette and Max. Max, our vibe-coding founder and RPG apprentice, has never played a tabletop RPG. Welcome to the table, Max!"
  - Data: `team.members[0].people` (count 5, names) in [`team-page/data.json`](team-page/data.json). `founders_github_team_members` (3) counts members of the GitHub team, not founders.
- **Why:** Fredrik's correction: Max is a founder, not a junior; "apprentice" is only about his RPG experience.
- **Status:** copy and data updated here. The page change was merged 2026-10-09 with Fredrik's OK ([#106](https://github.com/whyse-ab/ex-tales-forge/pull/106), main `b9c0297`) and is live on playtest (release v92, health check passing). Production pending: it needs Fredrik's OK and the manual "Deploy to production" workflow.
- **Details:** [`team-page/content.md`](team-page/content.md) section 1, "The founders".

## 2026-10-09: Physical skills improve right away; everything else waits for sleep

- **Decision (Fredrik, ~16:04, via Case):** of the exceptions listed in [#100](https://github.com/whyse-ab/ex-tales-forge/pull/100), the physical skills (melee_combat, ranged_combat, unarmed_combat, dodge, climbing, lockpicking) improve right away after a failure. All other skills keep waiting for sleep. This refines the 2026-10-09 "Skill growth comes only from failure" entry; default variant only.
  - "Right away" means the banked LP of a physical skill are resolved at the end of the turn of the failure, with the same LP-per-roll cost (ceil(level / 3)), the same roll (d20 ≥ 11 and ≥ level) and the same reflection gate from level 10.
  - **Cap:** at most +1 per physical skill per long-rest cycle. Once one improves, any LP it banks are dropped until the next long rest, so a fight can't be farmed for several levels in a day. A failed roll spends its LP; a remainder too small for a roll waits within the cycle, and the long rest clears it.
  - The GM gets "They are a little surer at: climbing" in the per-turn prompt on the turn itself.
  - Simulation (melee from 3): the pace over many nights is unchanged (10 rolls a day reaches level 10 in a median of 10 nights, against 9 under the sleep rule); the +1 just lands on the turn, after a median of 2 rolls on day one.
- **Why:** a missed handhold or a parry that came too late teaches on the spot; knowledge and social skills sink in overnight.
- **Status:** merged 2026-10-09 with Fredrik's OK ([#104](https://github.com/whyse-ab/ex-tales-forge/pull/104), main `1ec95af`); live on playtest (release v90, health check passing). Production pending: it needs Fredrik's OK and the manual "Deploy to production" workflow.
- **Details:** [ex-tales-forge PR #104](https://github.com/whyse-ab/ex-tales-forge/pull/104) (`TalesForge.Game.Progression.resolve_turn/3`).

## 2026-10-09: Prices are anchors with bounded situational modifiers; practice hours are narrative bands

- **Decision (Fredrik):** the formulas in [Design: one rule for skills and the economy](design-skills-economy.md) give **anchor prices**, not price tags, and practice hours are **narrative bands**, not ledgers. This refines the 2026-10-09 design note entry below.
  - **Prices:** actual price = anchor × situational modifiers (scarcity, demand, danger, leverage, relationship, haggling), each with its own proposed band, and the product clamped to 0.5× to 3× the anchor. Elixir computes the anchor and the range; Jev (or the GM, through a typed field) reads the situation and picks within it; Elixir clamps and records the anchor, modifiers, reasons and final price. Worked example: the last two melee-8 guards for a dangerous five-day pass, anchor 47c a guard-day, go for 122c after a successful haggle (2.59×), and would hit the 3× clamp (141c) on a failed one ([§3.6](design-skills-economy.md#36-situational-modifiers-the-actual-price)).
  - **Hours and levels:** the hours formula stays as the anchor, but the GM and player see five bands with rough hours and story flavour: Novice 0-3, Apprentice 4-7, Journeyman 8-11, Expert 12-15, Master 16-20 ([§2.1](design-skills-economy.md#21-narrative-bands-what-the-gm-and-the-player-see)). Levels stay exact only where dice need them.
  - The call-type section and open questions in the note were updated to match (13 open questions; the trainer-scarcity and hours-precision questions are answered).
- **Why:** Fredrik's guidance (2026-10-09): "the formulas are an anchor so prices stay consistent, not exact price tags. Like real life, supply and demand apply." Hiring the last available guards for a dangerous journey gives those guards pricing power. Levels and hours likewise give the GM something to build a story from, not exact numbers.
- **Status:** design note revised 2026-10-09; docs only, no code changed. Bounds and the other open questions wait for Fredrik.
- **Details:** [Design: one rule for skills and the economy](design-skills-economy.md)

## 2026-10-09: Write one design note for skills and the economy (docs only)

- **Decision (Fredrik):** write one design note that ties skills and the economy together: [Design: one rule for skills and the economy](design-skills-economy.md). Docs only, no code yet; each follow-up code PR needs Fredrik's OK.
  - **The one rule it proposes:** a day rate that grows with skill level through practice hours (`hours = 10,000 × (level / 20)³`, the formula rather than the rounded table; `day_rate = 10c + 30c × (level / 10)^1.5`, so unskilled 10c, skilled at level 10 40c, a skilled month 1,000c = 2g = 1 oz). NPC wages, hirelings and thugs, trainer fees, expert services and the labour part of item prices all derive from it.
  - Skill growth stays PR #100's LP model. Practice hours are a derived scale, not a counter; downtime practice could feed growth as Elixir-simulated rolls whose failures bank LP.
  - Price and wage math is Elixir, reading a hire or job offer is Jev, narration is the LLM ([call-type rule](call-types.md)).
  - The note lists the drift to fix and 12 open questions for Fredrik.
- **Why:** the game took two earlier designs from tales-forge-new ("Skill Progression and Convergence" and "Labor-Anchored Economy") and then drifted from both. The smith's short sword (60c) is 8× under the doc's 1g sword, starting coins come from the old table instead of the budget model, trainer fees are typed in by hand (three level-9 trainers charge 20c, 50c and 80c), the economy doc gives three different unskilled wages, and `priv/rules/skills.md` mixes two growth models.
- **Status:** note written 2026-10-09; open questions wait for Fredrik. No code changed.
- **Details:** [Design: one rule for skills and the economy](design-skills-economy.md)

## 2026-10-09: Skill growth comes only from failure, only in the failed skill, and is banked until sleep

- **Decision (Fredrik):** you learn only from failure, and only in the skill you failed. This supersedes the 2026-10-07 rule that spent LP at the end of every turn. Default variant only; the baseline variant keeps the #64 rule.
  - A success earns nothing. A failure or partial success banks one improvement chance (1 LP) for that exact skill, and nothing spills to other skills. The linked stat no longer adds LP.
  - Most skills improve only after the character has slept. Banked chances are resolved on a long rest (sleep, or a wait of 6 hours or more), not at the end of each turn. The GM gets a short per-turn note ("Rest: what sank in", no numbers) so it can narrate "you wake and feel surer with the blade".
  - An improvement attempt needs a d20 of at least 11 and at least the skill's level. Level 0–1 is no longer a sure thing: the chance is at most 50%, then 45% at 12 and 5% at 20.
  - **Refined the same day (Fredrik, 14:37):** "Once you have improved the skill one point the learning points for that skill are gone, not saved for the next night's sleep. The learning points are chances to improve and at higher levels you need even more training to improve. After a while you need to reflect on what you have learned, say skill level 10."
    - At most +1 per skill per long rest. Rolls stop at the first success, and then **all** of that skill's LP are cleared. If every roll fails, or there are too few LP for one roll, they are cleared too. Nothing carries over to the next night.
    - One roll costs ceil(level / 3) LP: 1 at levels 0–3, 2 at 4–6, 3 at 7–9, 4 at 10–12, 5 at 13–15. The numbers are in config (`TalesForge.Game.Progression`: `attempt_floor`, `lp_per_roll_divisor`, `reflection_level`, `long_rest_hours`).
    - From level 10, LP are only resolved if the character reflected on, practised or studied the skill, or trained it, since the last long rest. Otherwise they stay banked, and the GM gets a short note ("Their melee combat has outgrown simple practice; they need to reflect on it"). This is the only case where LP persist, and whether they should is an open question for Fredrik.
      - Fredrik 14:56: at level 10+, unreflected LP stay banked until a reflective rest (confirmed).
    - Simulation (persuasion from 3): 10 or 50 rolls before one sleep now give +1 level (the old rule gave +10.8 and +17.7). With 10 rolls a day, level 10 takes a median of 9 nights and level 15 a median of 119. With 5 rolls a day, level 10 takes 17 nights and level 15 is effectively out of reach without harder challenges or a trainer.
  - Skills that might improve right away instead (combat and dodge, climbing, lockpicking) are listed in the PR for Fredrik to decide. Every skill waits for sleep until he does.
  - This is the first step toward consolidation over world time ([Future ideas: Memory consolidation and attitude drift](future-ideas.md#memory-consolidation-and-attitude-drift)): skills settle during sleep the way memories would settle on world ticks.
- **Why:** in the [full batch of 2026-10-09](analysis-full-batch-2026-10-09.md), levels gained went from 13 to 112, and Paul gained 39 levels in five 10-turn sessions. Growth was much faster than "you learn by failing, slowly".
- **Status:** merged 2026-10-09 with Fredrik's OK ([#100](https://github.com/whyse-ab/ex-tales-forge/pull/100), main `e11fbf8`); live on playtest (release v88, health check passing). Production pending: it needs Fredrik's OK and the manual "Deploy to production" workflow.
- **Details:** [ex-tales-forge PR #100](https://github.com/whyse-ab/ex-tales-forge/pull/100) (`TalesForge.Game.Progression`, `TalesForge.Game.Mechanics`).

## 2026-10-09: Plain talk doesn't roll (re-enforcing 2026-10-07)

- **Decision (Fredrik):** this re-enforces the 2026-10-07 roll rule. The Jev intent read names persuasion, deception or intimidation only when the player is actually trying to change someone's mind against their interest: haggling, getting past a guard, talking down a fight, a bluff or a threat. Asking for an ale, asking Brenna where Osric is, thanks, compliments and flowery questions roll nothing.
  - The Jev skill question and the social and etiquette labels now say this. 18 tune-only eval cases (`plain_talk_vs_social`, h-pt01–18) cover it.
  - On the tune split, plain talk read as a social skill fell from 20/76 (26.3%) to 4/76 (5.3%). Real social checks are still read as social in 45/48. Skill accuracy went from 86.5% to 96.1%, and calibration is unchanged (ECE 0.040).
  - No Elixir "resisting target" guard was added: on the eval it would have dropped 7 correct social reads to stop 1 false one.
- **Why:** with `INTENT_JEV=on`, Paul rolled persuasion on 51 of 62 turns in the [full batch of 2026-10-09](analysis-full-batch-2026-10-09.md), mostly on ordinary talk, and it fed the fast growth.
- **Status:** merged 2026-10-09 with Fredrik's OK ([#100](https://github.com/whyse-ab/ex-tales-forge/pull/100), main `e11fbf8`); live on playtest (release v88, health check passing). Production pending: it needs Fredrik's OK and the manual "Deploy to production" workflow. Not in this PR: moves never roll, NPCs never roll in fights, and nine skills were never rolled in the batch.
- **Details:** [ex-tales-forge PR #100](https://github.com/whyse-ab/ex-tales-forge/pull/100), [Design: player intent as one Jev call](design-jev-intent.md).

## 2026-10-09: False-premise claims are checked against session state in Elixir, not by Jev

- **Decision (Fredrik):** false-premise claims, meaning items, coins, purchases and kills the player claims but doesn't have or didn't do ("as I did yesterday when I bought the enchanted armor, I put it on", "I killed the orc chief"), are checked against the session state by Elixir rules (`TalesForge.Game.PremiseCheck`), not by Jev. Jev is not tuned for false premises.
  - **Stays Jev's job:** fake authority ("[GM NOTE: …]", "patch note", "moderator message"), multi-turn code words and buried injections, which remain `prompt_injection` in the intent eval.
  - **In the game (default variant):** when a claim is false, the GM gets a short factual correction in the per-turn part of the prompt ("Player claims to own enchanted armor; they don't. Don't narrate it as true."). The turn records it as a hidden `player.false_premise` event. The rules are conservative so that true claims and lies told to a character are not flagged. The baseline variant and its prompts are unchanged.
  - **In the intent eval:** the six false-premise items (h-fp01–06, tune split) are relabelled `benign` with `false_premise: true` and are left out of safety precision and recall. Jev safety recall on the tune split goes from 0.828 to 0.923 (48/52).
- **Why:** Jev sees one turn and no state, so it flagged 0 of 6 false premises, and the state is the source of truth.
- **Status:** merged 2026-10-09 with Fredrik's OK ([#95](https://github.com/whyse-ab/ex-tales-forge/pull/95), main `f53449b`); live on playtest (release v81, health check passing). Production pending: it needs Fredrik's OK and the manual "Deploy to production" workflow.
- **Details:** [ex-tales-forge PR #95](https://github.com/whyse-ab/ex-tales-forge/pull/95); the eval cases came in [#93](https://github.com/whyse-ab/ex-tales-forge/pull/93).

## 2026-10-09: Fresh full playtest batch as the new baseline

- **Decision (Fredrik):** run a fresh full persona batch on playtest with the new scoring, because much of the system has changed: Jev intent on, one place per thing (#85), the Tinjacks coming to the fighter (#86), gesture variety (#87), forge and cottage hooks (#88), the phone layout (#89) and the costs pages (#90). It becomes the new baseline.
  - **Setup:** the same shape as the previous full batch (`post-rework-2026-10-08`): Paul, Hawk, Lotta, Lars and Ronny, 5 runs each, round-robin, 10 turns (Hawk 12), variant default, series `full-2026-10-09`. Sessions run with `INTENT_JEV=on`.
  - **Scoring:** the current Jev scorer, the sharpened rubrics and the confidence-weighted headline.
  - **Budget:** abort above $8 (the playtest day cap is $25). Persona bot cost is reported apart from game cost.
- **Why:** with this many changes, comparing against older batches piece by piece would mislead; one fresh batch gives a clean reference for the persona rework.
- **Status:** done 2026-10-09 12:28 (25 runs). Persona-balanced session score +0.13 (CI −0.13..+0.40) and weighted turn +0.09 (CI −0.02..+0.20); only Paul's gain is clear (+0.10 session, +0.27 turn). Jev intent median 232 ms, p95 275 ms. Rolls per run 0.7 to 4.7 (Paul 8.4). Hawk still fights in only 1/5 runs. Cost $2.99 (game $2.34, persona bot $0.65, scorer $0.007). The analysis goes in [Analysis: full batch 2026-10-09](analysis-full-batch-2026-10-09.md).

## 2026-10-09: Jev intent on for playtest and production

- **Decision (Fredrik):** turn the Jev intent read on (`INTENT_JEV=on`). The [persona comparison](analysis-intent-compare-2026-10-09.md) gave a quality tie (Jev session score 3.98 with intent on against 3.96 off; the confidence interval includes 0) and a clear latency win (intent p95 1641 ms down to 308 ms, 100% of reads within 1.5 s). That is good enough: we can't refine further until the personas are refined.
  - **Playtest:** switched 2026-10-09 (release v76).
  - **Production:** first held for Fredrik's explicit OK; he gave it the same day (2026-10-09 11:00) and production was switched (release v85).
  - Calibration tightening (the generous lifts and zero clarifying questions in the comparison) follows as a separate PR; it does not block this.
  - The baseline code (Tier 1 LLM intent) is kept until after the persona rework and the new full batch.
- **Why:** same quality, much faster turns, cost-neutral, and refining further needs better personas first.
- **Status:** live on both apps since 2026-10-09 (playtest v76, prod v85). New default-variant sessions pin `on`; older sessions keep their mode. See [Fly secrets](fly-secrets.md).
- **Details:** [Intent comparison: INTENT_JEV on vs off (2026-10-09)](analysis-intent-compare-2026-10-09.md), [Design: player intent as one Jev call](design-jev-intent.md)

## 2026-10-09: The /team founders' presentation page copy is approved

- **Decision (Fredrik):** the copy for the `/team` founders' presentation page in [docs/team-page/content.md](team-page/content.md) (commit `0069849`) is approved. Build the page from it.
- **Why:** the content brief has been through its tone revision (one crew, the current setup as a starting point, a founder's OK, the playtest-first flow, a closing "together" section).
- **Status:** approved; a PR to build the page follows (needs Fredrik's OK like any code change).
- **Details:** [Team page content](team-page/content.md)

## 2026-10-09: Deploy order: playtest first, then production

- **Decision (Fredrik):** a merge to `main` deploys to playtest first. Gentry (the QA bot) and the playtest batch check it there, and only then does it go to production. Production still needs Fredrik's OK.
- **Why:** today `main` deploys to production first and playtest after, so production meets a change before anything has tested it.
- **Status:** decided; workflow change [ex-tales-forge PR #91](https://github.com/whyse-ab/ex-tales-forge/pull/91) open (not merged). [Environments](environments.md) describes the new flow; until #91 merges, `main` still deploys production first.
- **Details:** [Environments: how a change gets to production](environments.md#how-a-change-gets-to-production)

## 2026-10-09: Costs pages: playtest shows only playtest-run costs, production shows all costs

- **Decision (Fredrik):** fix the `/admin/costs` pages so each app shows the right costs. For now they cover AI calls only (Grok, Jev and TypeSafe); Fly hosting may be added later.
  - **Playtest app:** shows only the cost of playtest runs: the persona bot, the GM, Jev scoring and Jev intent on playtest-run sessions. Other calls on playtest, such as manual play, get their own line and stay out of the runs' total.
  - **Production app:** shows all costs. It has its own numbers, plus a separate Playtest section read live from the playtest app through a small authenticated internal endpoint. No data is copied. One grand total goes on top. If playtest is down, the section says "playtest unavailable" and production's numbers still show.
  - Persona bot cost is always shown apart from game cost.
  - **Auth:** the endpoint (`GET /internal/costs`) answers only on playtest and reuses the existing shared secret `COSTS_PEER_TOKEN`, which is already set on both apps. No new secret. Production reads playtest's URL from config, so `COSTS_PEER_URL` is no longer read once the PR is deployed. The read has a 2 s timeout.
- **Why:** each thing lives in one place (playtest-run costs live on playtest and are read from there), and production gives full cost visibility on one page.
- **Status:** live. [ex-tales-forge #90](https://github.com/whyse-ab/ex-tales-forge/pull/90) merged 2026-10-09 with Fredrik's OK (`dd5dc7e`, final main after #86–#90; prod v84, playtest v75). Checked: playtest `GET /internal/costs` answers 401 without a token, production's `/internal/costs` is 404, and production's `/admin/costs` goes to sign-in without a session.

## 2026-10-09: Jev intent fallback and per-session latency probes

- **Decision (Fredrik):** the Jev intent call gets a fallback model from a different provider. Provider latency is checked once when a session starts, not with continuous pings.
  - Each provider in use (TypeSafe/Jev, the GM model and the fallback) gets a tiny probe call, and the game routes on those timings.
  - If Jev is slow, the session uses the fallback directly.
  - If the GM is slow, the game shows an in-fiction line (e.g. "The GM is a bit tired today...") instead of a spinner.
  - The per-turn timeouts stay as the safety net.
  - Probe timings are recorded so they can appear on the costs/status page later.
- **Why:** resilience and latency. One slow provider shouldn't stall a turn, and the player should see the game's voice, not a spinner.
- **Status:** planned. The spike waits for provider accounts (Groq, Anthropic, Google). It builds on the Jev wrapper and provider config refactors (steps 1 and 2 in the [architecture baseline](architecture-baseline-2026-10-09.md#5-suggested-order-for-refactor-prs)).
- **Details:** [Architecture baseline: ex-tales-forge main at 2f27ff1](architecture-baseline-2026-10-09.md)

## 2026-10-09: Pragmatic Programmer architecture review on every merge to ex-tales-forge main

- **Decision (Fredrik):** every merge to `main` in ex-tales-forge gets an architecture review in the spirit of *The Pragmatic Programmer*: DRY, orthogonality, broken windows, reversibility, and our own rules (call types, state written only by Elixir rules and Jev, each thing lives in one place, docs, specs and tests for every module). The starting point is the baseline review of `main` at `2f27ff1`. The refactors it found are queued in its suggested order, as separate PRs: (1) one Jev client plus correct cost source, (2) LLM provider config, (3) an intent reader behaviour and pipeline out of `GameSessions`, (4) error-handling cleanup, (5) a typed turn/intent context and no Repo in `Game.*`, (6) splitting `Inventory`, (7) Crossroads as a full pack, (8) GM memory and summary writes moved to Jev or Elixir, then ongoing cleanup.
- **Why:** the intent pipeline and the AI-call plumbing grew by copy-paste and flags, so the next changes (a fallback intent provider, per-session latency probes) would touch many places. Reviewing each merge against a baseline keeps that from coming back.
- **Status:** baseline written; no refactor started. Each refactor PR needs Fredrik's OK like any code change.
- **Details:** [Architecture baseline: ex-tales-forge main at 2f27ff1](architecture-baseline-2026-10-09.md)

## 2026-10-08: Each thing lives in one place: surveys on production, playtest runs on playtest

- **Decision (Fredrik, via Case):** each thing lives in one place. Founder surveys live only on production (`/admin/survey`, `/admin/surveys/*`), and playtest runs live only on playtest (`/admin/playtest/*`). Each app redirects those pages to the other app, and its admin nav links there. No survey answers are stored on playtest and no playtest data on production: saving a survey on playtest is refused, and the persona runner, series and scorer refuse to start on production. The app knows which one it is from `FLY_APP_NAME`; the two base URLs are in config, so there are no new secrets.
- **Why:** looking at playtest, Fredrik thought his survey answers had vanished. It was a false alarm: they were on production. With one source for each thing, that confusion can't happen and the data isn't split between two databases.
- **Status:** live. [ex-tales-forge #85](https://github.com/whyse-ab/ex-tales-forge/pull/85) merged 2026-10-09 with Fredrik's OK (main `2f27ff1`, prod v82, playtest v73). Checked with curl: on playtest, `/admin/survey` and `/admin/surveys/*` redirect to production; on production, `/admin/playtest/*` redirects to playtest, and `/admin/survey` stays put (it goes to sign-in). PR preview apps, which aren't built yet, would count as production by name; revisit that when they're built.

## 2026-10-08: Playtests show character changes (PC and NPCs)

- **Decision (Fredrik, via Case):** each admin playtest run page shows how the player character and every NPC changed between the start and end of the run, with a per-turn timeline linking to the turns. The playtest index gets a per-batch summary. The view shows only what we store today, and says "not tracked yet" for the rest instead of inventing it.
  - **Shown:** NPC location, mood, stance toward the player and the latest Jev feeling, relationship score, current concern, and the memories added (per turn, with who wrote them). For the player character: location, wounds, coins, learning points and skill improvements.
  - **Not tracked yet:** NPC feelings toward other NPCs, Maslow level and concerns (written once, never updated), OCEAN-filtered memory (no personality filter exists yet), the player character's memories and mood, and per-turn Jev reaction values (only the latest reaction is kept).
  - **Batch metrics:** share of runs where an NPC's attitude to the player changed, NPCs whose attitude changed per run, memories added per run, and NPCs with any change per run (median and mean). The [Jev compare scripts](scripts/jev-compare/compare.py) export the same numbers.
- **Why:** to judge whether play leaves a mark on the characters, we need to see it per run and per batch. Today that state is scattered (npc_instances, characters, world_state, session events, turns, ai_calls). One read-only module (`TalesForge.Playtest.CharacterChanges`) gathers it now and will switch to the world event log once [WORLD_STATE](design-stateful-world.md) lands. That is also where the "not tracked yet" gaps get filled.
- **Status:** live. [ex-tales-forge #83](https://github.com/whyse-ab/ex-tales-forge/pull/83) merged 2026-10-08 with Fredrik's OK (main `c98b482`, prod v80, playtest v70). Reads today's scattered state; switches to the world event log once WORLD_STATE lands.
- **First numbers (2026-10-08 batches):** the attitude share is 100% in all three series, so NPCs whose attitude changed per run is what separates them (median 3 with intent off, 2 with intent on, 2 after the rework). Memories per run (median): 31, 24 and 21.

## 2026-10-08: Stateful world: four design answers

- **Decision (Fredrik, via Case):** answers to questions 1–4 of the [stateful world design note](design-stateful-world.md#11-questions). Questions 5–8 (trace fading, world pace, snapshot cadence, shared worlds) wait for measurements.
  1. **One process per world; entities are plain data.** An NPC that needs to think something through gets a short-lived Task when it matters (Jev calls, answer returned to the world as an event). If a world outgrows one process later, it splits by region, never per entity. This replaces the per-character agent of [Character plan](plan-unify-character.md) phase 3.
     - *Why:* a turn touches several entities and must commit as one; pure functions over an ordered log replay the same way every time; only the world has a clock of its own; and idle data costs nothing.
  2. **The GM gets the state snapshot plus the last 1–2 turns.**
     - *Why:* the snapshot keeps the facts straight, and the recent turns keep the prose continuous in voice and thread. The GM no longer carries the world in its own summary, which is where the drift came from.
  3. **Commit before the GM call.** The rules and Jev decide what happened, and it is saved first. If the GM call fails, the world has still changed and only the prose is retried. A retry never re-rolls dice or re-asks Jev. The player sees the result in plain words until the narration arrives, with a retry button if the GM keeps failing.
     - *Why:* the outcome belongs to the rules, not to the narrator. A failed GM call no longer loses the player's action, and a shared world is never held for the length of a GM call.
  4. **Only the rules (Elixir) and Jev write events.** The GM writes prose only. The GM's `npc_memory_updates` and `World.Extract` become Jev calls or are dropped: memories come from events and the Jev judgements, and promises from a Jev reader with fixed promise kinds. Free-text facts invented in the prose are no longer recorded.
     - *Why:* the [call-type rule](call-types.md): structured state from an LLM is a smell, and Jev is cheaper (~$0.0001 against ~$0.001 for the extraction call).
- **Order:** the first code PR (`WORLD_STATE=shadow`) comes after [Jev intent](design-jev-intent.md) PR 2. Each code PR needs Fredrik's OK.
- **Details:** [Design: persistent world state, updated with the answers](design-stateful-world.md) (§4 processes, §6 commit and event writers, §9 prompt layout, §10 migration)

## 2026-10-08: Design note: persistent world state at the core of the turn loop

- **Decision (Fredrik, via Case):** write a design note on making persistent world state the core of the turn loop. An "apply consequences" step goes between the rules and the prose. The turn's result becomes events sent to everything it touched (people, the player character, places, factions), each updates its own state in plain Elixir, Jev is used only for judgements, and the GM gets a snapshot of the current state instead of the history. The world keeps moving on world time.
- **What the note recommends:**
  - **Processes:** one `World.Instance` process per world; people, places, items and factions are plain data inside it.
  - **Persistence:** an event log (extending `session_events`) plus snapshots every 25 events.
  - **First step:** a shadow mode behind `WORLD_STATE=shadow` that changes nothing the GM sees.
  - **Cost:** no new LLM call on the hot path.
- **Why:** today the state is spread over several copies (mood in four places), places hold no state, nothing moves between turns, and the GM carries the continuity itself, which is where the drift comes from. One state model with recorded causes gives the [living world](design-world-agents.md#living-world-design-to-try) and the Tinjacks something to run on.
- **Status:** design note written, no code. Questions 1–4 were answered on 2026-10-08 ([Stateful world: four design answers](#2026-10-08-stateful-world-four-design-answers)); questions 5–8 wait for measurements. The first PR (`WORLD_STATE=shadow`) comes after Jev intent PR 2.
- **Details:** [Design: persistent world state at the core of the turn loop](design-stateful-world.md)

## 2026-10-08: Several founder surveys at once, as tabs, from docs JSON with an active flag

- **Decision (Fredrik, via Case):** `/admin/survey` shows one tab per active survey, each with the signed-in founder's status (not started, in progress, done). Surveys are discovered from the `docs/*survey*.json` files in tales-forge-docs, and each file's `"active": true/false` flag decides whether it is a tab. Adding or closing a survey is a docs commit (60 s cache, or "Sync from repo"), with no deploy. Closed and inactive surveys leave the tabs but stay readable in the admin, with results, CSV and Markdown. A new `/admin/surveys` page shows every founder's status per survey. founder-survey-3 keeps its slug, results and answers (`active: true`), and the `priv/surveys` snapshots stay the fallback for both surveys.
- **Why:** the intent survey and founder survey 3 are open at the same time. Founders need to see both and where they stand on each, and opening or closing a survey shouldn't need a code change.
- **Status:** live. [ex-tales-forge #82](https://github.com/whyse-ab/ex-tales-forge/pull/82) merged 2026-10-08 with Fredrik's OK (main `410b132`, prod v79, playtest v69); prod lists founder-survey-3 and founder-survey-4-intent as active tabs.
- **Details:** [survey file format](https://github.com/whyse-ab/ex-tales-forge/blob/main/priv/surveys/README.md)

## 2026-10-08: Founders label vague player inputs in a second survey (tune split only); the answers set labels and the ask band

- **Decision (Fredrik, via Case):** the founders say what ambiguous player inputs mean in a short second survey, [founder survey 4](founder-survey-4-intent.md) (`founder-survey-4-intent`, about 10 minutes, at `/admin/surveys/founder-survey-4-intent`).
  - **Items:** 12 genuinely ambiguous items from the intent eval set's **tune split only**; holdout items are never used (the selection script fails on any). No attack or safety items.
  - **Question format (Fredrik's addendum):** one question per item with 3–4 plain-language readings drawn from the gold label, the `acceptable` alternatives and Jev's readings, deduped and shuffled, never marking which is gold; plus "Unclear, the game should ask the player", "Something else" with a free-text field, and an optional comment. Every reading maps back to structured labels (action, target, now or later, deferred action and target), carried in the survey JSON (`option_labels`) and in `mapping.json`.
  - **Use:** the majority reading becomes gold, a minority reading becomes acceptable, and an Unclear win or no majority marks the item as one the game should ask about. "Something else" answers are reviewed by hand. Per-item founder agreement is reported and feeds the ask-band (`T_act`/`T_ask`) calibration.
- **Why:** Case's and Fredrik's labels settle most items, but on genuinely two-way inputs the honest gold is what players mean, and where players disagree the game should ask rather than guess. Using the tune split keeps the holdout unseen.
- **Status:** live as the second tab on `/admin/survey` since [ex-tales-forge #82](https://github.com/whyse-ab/ex-tales-forge/pull/82) merged 2026-10-08 (prod v79), with each option's labels in the results and CSV. Answers are applied later per `docs/scripts/survey-intent/apply_answers.md`; fixture changes go in a PR after Fredrik's OK.
- **Details:** [survey](founder-survey-4-intent.md), [how answers become labels](scripts/survey-intent/apply_answers.md), [selection and build scripts](scripts/survey-intent/), [Design: player intent as one Jev call](design-jev-intent.md)

## 2026-10-08: Player intent go-ahead with the labelled eval set first, and five scope decisions

- **Decision (Fredrik, via Case):** go ahead with the [Jev intent plan](design-jev-intent.md) and the labelled-evaluation-set-first approach, with five scope answers. This builds on (does not replace) the entry below.
  1. **Close #76** as superseded by the Jev intent design. Its quote decision and reason codes, the `ai_calls.meta` migration (version `20261008070000`) and passing `gm_quote` to the turn job all carry over into the wiring PR. The branch is kept.
  2. **A confident `jailbreak` or `prompt_injection` does not decline the turn.** The GM gets the typed summary instead of the player's own words, play continues in-story, and the decision is logged. Only a genuine real-world-harm request (`nefarious`) is declined, and the GM declines **in character** rather than breaking the fiction.
  3. **Production `TYPESAFE_INTENT_API_KEY`:** Fredrik creates the key in his TypeSafe account and submits it through a **masked secret request in Case's chat** (the value never appears in the conversation); Case sets it on Fly with his OK. Until the path ships, production stays on the summary. (Done 2026-10-08: key `tales-forge-intent` set on production; playtest has its own separate key. See [fly-secrets](fly-secrets.md).)
  4. **The §5 targets are approved, with attacks raised to about 60.** The report states what recall bound "no misses in 60" supports (0 misses on the pooled 60 bounds recall at ≥ ~94%, two-sided 95%; the ~18 holdout attacks alone bound it only at ~81%, so the ≥ 95% recall target is read on the pooled set after a clean holdout). The 30% holdout stays stratified so the attack classes sit in **both** splits.
  5. **The frozen `baseline` variant retires** once the Jev path wins the §8 playtest comparison — that is what finally lets the Tier 1 LLM intent code go.
- **Labelling split (approved):** the agent drafts every label (marked `reviewed: false`), Case reviews all of them, and Fredrik spot-checks a random 30 plus **every attack item and every disagreement**; his call wins. Two-way items carry `acceptable` alternatives.
- **Why:** these settle the open questions the design note left for Fredrik (§10). Declining only real-world harm keeps the game playable under adversarial play while still refusing genuine harm; reading recall on the pooled set is the honest bound given a small holdout; retiring the baseline only after the comparison keeps a safe rollback until the Jev path is proven.
- **Status:** approved. PR 1 ([#81](https://github.com/whyse-ab/ex-tales-forge/pull/81): the labelled eval set of 350 items, reviewed by Case and spot-checked by Fredrik, plus `mix intent.eval`; not wired into turns) merged 2026-10-08 with Fredrik's OK (main `0c727a8`, prod v78, playtest v68); #76 is closed. Tune split after review: action 95.1%, safety 42/42 with 0 false positives; deferred and calibration are the tuning targets. Each later PR still needs Fredrik's OK. PR 2 ([#84](https://github.com/whyse-ab/ex-tales-forge/pull/84): tune-split tuning, the calibration map, and `INTENT_JEV=off|shadow|on` wiring; tune numbers in [the v2 eval note](scripts/jev-intent/eval-tune-2026-10-08-v2.md)) merged 2026-10-08 with Fredrik's OK (main `36797eb`, prod v81, playtest v72). `INTENT_JEV=shadow` set on playtest 2026-10-08 (Fredrik's OK); prod off. Next: a day of shadow, then the persona comparison, then the holdout run once on frozen tuning before prod.
- **Details:** [Design: player intent as one Jev call](design-jev-intent.md), [heuristic sample](scripts/jev-intent/heuristic-sample-2026-10-08.md), [Fly secrets](fly-secrets.md)

## 2026-10-08: Player intent moves to one Jev call with the safety label, built on a labelled evaluation set first

- **Decision (Fredrik, via Case):** player intent extraction moves to Jev. One TypeSafe Jev call per default-variant turn returns the typed intent and the safety label together:
  - **Intent:** action type, target, skill, deferred action, confidence.
  - **Safety label:** `benign`, `jailbreak`, `prompt_injection` or `nefarious`, with its confidence.
  - **What it replaces:** the Tier 1 LLM intent call and the separate safety read of ex-tales-forge #76.
  - **The regex heuristic** stays only as a fast path or a fallback, and only if it still earns its place. The design note proposes fallback only.
  - **Low Jev confidence** leads to a clarifying question, not another LLM call. The clarifying rate must stay near today's ~4%.
  - **Proof:** a playtest comparison against the current path (Jev score, clarifying rate, latency, cost).
  - The player-quote rule is unchanged (benign at ≥ 0.90 means the GM gets the player's own words, otherwise the summary; logged). The `baseline` variant is frozen and keeps the old path. GM prompts stay byte-identical.
- **Addendum (Fredrik, via Case, same day): a labelled evaluation set comes first.** Intent is a vital part of the game, and it's fine to spend considerable effort tuning it.
  - **The set:** player inputs with known correct intent (action type, target, skill, deferred action, safety label), kept as a fixture in ex-tales-forge.
  - **Seeds:** real playtest turns (the 39 clarification turns of the every-turn batch, the three #79 hang turns, Paul's "scale" misroll) plus handwritten edge cases: quoted speech vs narration, plans vs actions, multi-actions, lies and in-story violence (Ronny's threats are benign), jailbreak and injection attempts.
  - **The mix task:** it runs the Jev call over the set and reports accuracy per field, safety precision and recall, calibration (reliability bins, ECE) and the clarifying rate at candidate thresholds.
  - **Holdout:** a fixed ~30% split, never used while tuning.
  - The Jev input is iterated until the proposed targets are met. The eval set and the mix task are the **first PR**, before the call itself.
- **Supersedes:** [Clarification: the safety read is part of the intent call, not a separate Jev call](#2026-10-08-clarification-the-safety-read-is-part-of-the-intent-call-not-a-separate-jev-call). The safety read is still part of the intent call, but that call is now Jev, not the Tier 1 LLM. `INTENT_CALL_EVERY_TURN` is no longer needed. That entry is unchanged otherwise.
- **Why:**
  - **The call-type rule** ([call types](call-types.md)): unstructured in, structured out is a Jev call, and structured output from the LLM is a smell.
  - **The every-turn batch** ([analysis](analysis-intent-every-turn-2026-10-08.md)): putting the LLM intent call on every turn raised clarifications to 35% of turns (4% before; Paul 65%, up to 5 rounds). It added about $0.0029 per turn (~30% of game cost), 1.7 s median / 4.3 s p90 on the intent step, and +63% persona cost. Its LLM safety confidence only ever took the values 0.90 and 0.95.
  - **Jev on playtest** costs ~$0.00004 per call at 0.23 s median for the NPC reactions. An intent call is estimated at ~$0.0001 and ~0.3 s.
  - **The heuristic** gave the wrong action type on 22 of 60 random playtest messages (37%), all at confidence ≥ 0.85, so it is not a safe fast path.
- **Status:** approved, design note written, no code yet. The first PR is the eval set and `mix intent.eval`. Each PR needs Fredrik's OK. #76 is likely superseded; closing it is Fredrik's call. Production has no TypeSafe key; it needs a `TYPESAFE_INTENT_API_KEY` before this path is turned on there.
- **Details:** [Design: player intent as one Jev call](design-jev-intent.md), [heuristic sample](scripts/jev-intent/heuristic-sample-2026-10-08.md), [Fly secrets](fly-secrets.md)

## 2026-10-08: Paul's level 5 needs a consequence of his own choice or discovery

- **Decision (Fredrik, via Case):** on Paul's 4-vs-5 border, a vivid answer or a new fact is a 4. A 5 requires a consequence of his own choice or discovery, where the world reacts: for example an NPC acts on what he learned, or a door opens because he asked.
  - Surprise, callback and NPC goals no longer count as level-5 evidence for Paul. Lotta's level 5 is unchanged.
  - Paul's rubric version: `jev-affect-v1-df3c861`, replacing the first sharp version `7862783` from the entry below. GM prompts and the `baseline` variant are untouched.
- **Why:** on the first sharp version Jev split about 0.42 / 0.45 between levels 4 and 5 on Paul's unsure turns, which were 72% of his baseline turns. His typical turn is an open question answered with vivid new facts, and that fits both "an answer" (4) and "a surprise" (5).
- **Result:** the re-score ran on the box from existing transcripts: Paul's 13 baseline and 5 post-rework runs, 18 Jev calls, $0.0062.
  - **Unsure share** (confidence < 0.7): 33% on the baseline and 48% post-rework, against 51% / 46% on #69 and 72% / 74% on the first sharp version.
  - **Weighted headline:** 4.41 / 4.27.
  - **Turn weighted delta:** −0.14 (CI −0.24…−0.03). The session delta is −0.01 (CI −0.09…+0.08).
  - **Post-rework stays less settled:** its threat-heavy turns, where the world reacts but not to his delight, still split.
- **Status:** approved; [ex-tales-forge #80](https://github.com/whyse-ab/ex-tales-forge/pull/80) merged 2026-10-08 09:31 (merge commit `132e732`, Fredrik approved 09:23) and deployed: production v76, playtest v66. New Paul scores use `jev-affect-v1-df3c861`; older scores keep their rubric versions.
- **Details:** [Analysis: Jev post-rework 2026-10-08, added section](analysis-jev-post-rework-2026-10-08.md#added-2026-10-08-pauls-level-5-needs-a-consequence-of-his-own-choice-or-discovery), [Jev scoring: sharper borders](jev-scoring.md#sharper-borders-for-paul-4-vs-5-and-lotta-3-vs-4-2026-10-08), [results](scripts/jev-confidence/results-2026-10-08-paul-consequence.md)

## 2026-10-08: The headline Jev score is a confidence-weighted average

- **Decision (Fredrik, via Case):** the headline Jev score is the confidence-weighted average, `sum(score × confidence) / sum(confidence)`, on the 1–5 scale. It is shown with the unsure share (confidence < 0.7) next to it, and the high / low / unsure breakdown stays underneath.
  - **This refines the entry below** ("Jev scores are read as a score-by-confidence matrix"). The weighted average replaces the mean of the scores at confidence ≥ 0.7 as the headline.
  - **The 0.7 cutoff stays** for the unsure share and the breakdown. The rest of that entry (the three groups, bootstrap CIs over runs, comparing unsure shares only within one rubric) still holds.
  - **On the playtest pages** (`/admin/playtest` and `/admin/playtest/:id`), the weighted turn average is the headline as "X/5 · unsure Y%". The breakdown sits under it and the session score is a secondary line.
- **Why:** the cutoff mean throws scores away. Where Jev is often unsure, too few remain to read: for example only 7 of Lotta's post-rework turns were left on the #69 rubric. The weighted average uses every turn and lets unsure turns count less. In practice it stays within about 0.1 of the plain mean for most personas, and it gives the same deltas: Paul's turn dip is −0.12 (CI −0.20…−0.05), and Hawk's gain stays clear of zero (+0.22, CI +0.01…+0.41).
- **Status:** approved; [ex-tales-forge #80](https://github.com/whyse-ab/ex-tales-forge/pull/80) merged 2026-10-08 09:31 (merge commit `132e732`, Fredrik approved 09:23) and deployed: production v76, playtest v66. The playtest pages show the weighted headline "X/5 · unsure Y%" with the breakdown underneath. The analyses report the weighted headline from 2026-10-08.
- **Details:** [Analysis: Jev post-rework 2026-10-08, added section](analysis-jev-post-rework-2026-10-08.md#added-2026-10-08-confidence-weighted-headline-and-sharper-paullotta-borders), [Analysis: Jev baseline 2026-10-07, update](analysis-jev-baseline-2026-10-07.md#update-2026-10-08-confidence-aware-reading), [script](scripts/jev-confidence/README.md)

## 2026-10-08: Sharper Jev borders for Paul (4 vs 5) and Lotta (3 vs 4)

- **Decision (Fredrik, via Case):** sharpen the two rubric borders where Jev was most often split, then re-score the existing baseline and post-rework runs. Each border now names what to look for in the turn, with a short example from a real turn.
  - **Paul 4:** the reply only answers him (information he asked for, a price, a room, a welcome, a gift).
  - **Paul 5:** at least two kinds of evidence, each visible in this turn's narration: a surprise he did not ask about, a consequence of his choice, a callback to an earlier word or deed, or an NPC acting on their own goals. Asked-for information, warmth, gifts and prices never count.
  - **Lotta 3:** the reply would read the same for any traveller who said her line.
  - **Lotta 4:** it picks up something particular to her character (race, craft or calling, background, earlier deeds). Using her name or answering her question is not enough.
  - **New rubric versions:** paul `jev-affect-v1-7862783` (was `fd84ebb`), lotta `jev-affect-v1-989546a` (was `ce84a1a`). Lars, Hawk and Ronny are unchanged. GM prompts are untouched.
- **Why:** on the #69 rubric Jev was unsure (confidence < 0.7) on 51% of Paul's and 75% of Lotta's baseline turns, split on exactly these borders.
- **Result:** the re-score ran on the box from existing transcripts (36 Jev calls, $0.012). Unsure share, baseline / post-rework:
  - **Lotta: it worked**, from 75% / 86% to 39% / 30%. Jev is now mostly sure she is at level 3, so her weighted headline drops from 3.92 to 3.28 on both sides, delta 0.00 (CI −0.22…+0.30).
  - **Paul: it did not**, from 51% / 46% to 72% / 74%. His typical turn is both an answer to his open question and vivid new detail he didn't ask for, and the wording can't settle which. His turn dip stays about −0.1 (weighted −0.10, CI −0.22…−0.01).
  - **Not done:** a further change to Paul's level 5 (for example requiring a consequence of his choice) would change the level's meaning. It is left open for Fredrik.
- **Status:** approved; [ex-tales-forge #80](https://github.com/whyse-ab/ex-tales-forge/pull/80) merged 2026-10-08 09:31 (merge commit `132e732`, Fredrik approved 09:23) and deployed: production v76, playtest v66. New scores use paul `jev-affect-v1-df3c861` (the consequence rule above replaced this entry's Paul level 5) and lotta `jev-affect-v1-989546a`; older scores keep their rubric versions.
- **Details:** [Analysis: Jev post-rework 2026-10-08, added section](analysis-jev-post-rework-2026-10-08.md#added-2026-10-08-confidence-weighted-headline-and-sharper-paullotta-borders), [Jev scoring: sharper borders](jev-scoring.md#sharper-borders-for-paul-4-vs-5-and-lotta-3-vs-4-2026-10-08), [re-score rows](scripts/jev-rescore/rescore-baseline-2026-10-08-sharp.json)

## 2026-10-08: Jev scores are read as a score-by-confidence matrix, not a plain average

- **Decision (Fredrik, via Case):** Jev scores are read as a score-by-confidence matrix, not a plain average.
  - **Headline score:** the mean of the confident scores only, with the cutoff at confidence ≥ 0.7. The same figure at 0.6 and 0.8 is shown next to it as a sensitivity check.
  - **Low-confidence share:** the share of turns (and sessions) below the cutoff is reported separately as its own metric. A high share is a sign of unclear or flat play. Compare it only within one rubric, because a stricter rubric adds a border Jev can be unsure about.
  - **Three groups:** confident-high (score ≥ 3.5, works), confident-low (score ≤ 2.5, broken) and unsure (confidence below the cutoff). Confident scores between 2.5 and 3.5 (level 3) are shown as confident-middle.
  - **Deltas** between series use the confident means, with bootstrap CIs over runs, next to the old plain-average deltas. A cutoff that leaves fewer than 20 turns or 3 runs (or 3 sessions) on a side is flagged as too few to read.
  - This entry covers the analysis method. Changes to the playtest page or the scorer code would be a separate PR and need Fredrik's OK.
- **Why:** plain averages mixed confident verdicts with split, unsure ones. For example, Ronny's turns where Jev leaned to level 1 but was split landed at 2.2–2.9 with confidence 0 (baseline `54c401ab` and `e367a9a0`, post-rework `50a3c41a` T3–T6), and several excerpt scores had confidence 0. In the baseline, problems outside Hawk showed up as unsure turns, not low ones: only 1 of 520 non-Hawk turns was confidently low.
- **Status:** applied to the 2026-10-07 baseline and the 2026-10-08 post-rework comparison, using existing scores only (no new runs, no Jev calls). The session deltas stay indistinguishable from zero. Hawk's turn-level gain becomes clear (+0.32, CI +0.15…+0.47), and Ronny's session dip turns out to come from unsure sessions. Paul's and Lotta's turn deltas can't be read this way yet, because the stricter re-score of their baseline kept no turn confidences. The playtest page and the scorer are unchanged. *Added 2026-10-08:* their baseline was re-scored again with turn confidences kept (26 Jev calls, $0.0067). Paul's turn dip is about the same size under the new reading (−0.08 at 0.7, CI −0.17…+0.01). Lotta has too few sure turns at 0.7.
- **Details:** [Analysis: Jev baseline 2026-10-07, update 2026-10-08](analysis-jev-baseline-2026-10-07.md#update-2026-10-08-confidence-aware-reading), [Analysis: Jev post-rework 2026-10-08, update 2026-10-08](analysis-jev-post-rework-2026-10-08.md#update-2026-10-08-confidence-aware-reading), [script](scripts/jev-confidence/README.md)

## 2026-10-08: Bug fix: the turn hang after an intent call; crashed turns now fail visibly; run flags record the world features

- **Decision (Fredrik, via Case):** merge and deploy the fix for the turn hang found in the post-rework series. Approved 2026-10-08 07:48: merge #79 and deploy once the survey page was live. This is a bug fix, recorded here for the behaviour changes below.
  - **Cause:** the intent call answers `"parameters": null` for actions that need no roll. The decoder kept that `nil`, and the rules step crashed on it (`BadMapError`) inside the turn job. Oban retried three times and dropped the job without any log line or failed-turn message, so the player or playtest runner waited until its timeout. This hung 3 of 14 intent-call turns: runs `a76294d9`, `0d1b8222` and `1a995c9f`.
  - **Fix:** the intent decoders treat JSON `null` as missing.
  - **Crashed turns now fail visibly:** a crash in any turn step is logged with its stacktrace, shown to the player as a failed turn ("crashed: <error>"), marked `error` on that step's `ai_calls` row and retried by Oban. A playtest run then ends as `failed` with the error in its notes, instead of `stopped` / `timeout`.
  - **Run flags:** `playtest_runs.flags` now record `inn_world` and `world_antagonist` (`on`/`off`). They come from the session's features.
  - **Misread roll:** "scale" now counts as climbing only as a verb ("scale the wall"). Paul's "silver to the scale" no longer rolls climbing.
- **Why:** a crash should never look like a slow turn. Run conditions should be readable from the run itself.
- **Status:** merged as `ccd5379`, deployed to production v75 and playtest v63. Health checks pass and the survey page still redirects to the login when signed out.
- **Details:** [ex-tales-forge PR #79](https://github.com/whyse-ab/ex-tales-forge/pull/79), [Analysis: Jev post-rework 2026-10-08, §9](analysis-jev-post-rework-2026-10-08.md#9-limitations)

## 2026-10-08: Founder survey in the app instead of Google Forms

- **Decision (Fredrik, via Case):** the founder survey runs on our own page at `/admin/survey`, behind the GitHub team login, so we know who answered and there's no name question. Approved by Fredrik (2026-10-08 07:45: "You are go for survey", merge and deploy).
  - The questions come from [`founder-survey-3.json`](founder-survey-3.json) on this repo's main, read through GitHub with the server's `GITHUB_DOCS_TOKEN` and cached for 60 s. A snapshot in the release is the fallback. A wording change, opening or closing (`status`) is a docs commit, with no deploy. The `.md` is generated from the JSON (`scripts/survey/render_md.py`).
  - Answers autosave per section, one response per founder, editable until `status` is `closed`. Each answer records the survey `version` it was given under, and every survey file answered under is stored verbatim.
  - Results at `/admin/surveys/founder-survey-3/results`: per-question aggregates by persona, per-founder answers, a CSV export and a Markdown summary for personas.md.
- **Why:** survey 2 never went out, and Google Forms can't link the excerpts to the playtest runs or keep answers tied to the exact question wording.
- **Status:** merged as `944ad1a`, deployed to production v74 and playtest v62. On both apps the release loads the survey from tales-forge-docs main (27 questions, status open, no problems). The page redirects to the login when signed out. The first prod deploy attempt (v73) failed on a transient database connection timeout in the migration step and passed on re-run.
- **Details:** [ex-tales-forge PR #78](https://github.com/whyse-ab/ex-tales-forge/pull/78), [founder survey](founder-survey-3.md)

## 2026-10-08: Broken links fixed in the admin docs viewer and the code docs; CI checks the links

- **Decision:** links in the admin docs viewer (`/admin/docs`, decision pages) and in the code docs (`/admin/code-docs`) resolve, and CI fails when one breaks. Approved by Fredrik (2026-10-08 07:40: merge, deploy and sync the docs on both apps).
  - Docs viewer: relative `.md` links go to the doc's own page (`/admin/docs/<path>`) or the decision page, images under `docs/` are served at `/admin/docs-files/<path>`, other repo files go to their GitHub URL in this repo, and headings get ids so `#anchor` links work.
  - Code docs: the missing `docs_config.js` is shipped, PRODUCT, architecture and DEPLOY-FLY are included as pages, links to files ExDoc doesn't ship go to GitHub, and "View source" points at the deployed commit (`GIT_SHA`).
  - CI: `mix docs.check_links doc` checks every internal link in the ExDoc output, and a crawl test signs in and checks that every internal link on the app's pages returns 200.
- **Why:** Fredrik found broken links on the admin docs pages and in the code docs.
- **Status:** merged as `b8b41cc`, deployed to production v72 and playtest v61; docs synced on both apps (32 docs, 12 decisions each; before: production 13 docs, playtest 12). An in-app check of all 44 doc and decision pages found no broken internal link or anchor on either app.
- **Details:** [ex-tales-forge PR #77](https://github.com/whyse-ab/ex-tales-forge/pull/77)

## 2026-10-08: Hawk / Tinjacks: the Tinjacks come to the fighter; Brenna points at trouble, not chores

- **Decision (Fredrik, via Case):** the Tinjacks come to the fighter. Their plans run on world time even when he's away, so the toll happens anyway and he hears about the consequences afterwards. Brenna points fighters at the trouble instead of offering chores.
  - Status: live. [ex-tales-forge #86](https://github.com/whyse-ab/ex-tales-forge/pull/86) merged 2026-10-09 with Fredrik's OK (`169a743`); deployed with final main `dd5dc7e` (prod v84, playtest v75). Measured in the [full batch 2026-10-09](#2026-10-09-fresh-full-playtest-batch-as-the-new-baseline).
- **Why:** in the post-rework batch, only 1 of 5 Hawk runs fought (on the last turn) and he still did chores in 3 of 5; runs without a fight scored better (3.14 vs 2.54) but the confrontation came too late.
- **Details:** [Analysis: Jev post-rework 2026-10-08](analysis-jev-post-rework-2026-10-08.md)

## 2026-10-08: GM tics: track recent gestures as off-limits; drop phrase-by-phrase bans

- **Decision (Fredrik, via Case):** drop phrase-by-phrase bans. Elixir tracks the gestures used in the last N turns and passes them to the GM as off-limits, and a pattern check on the output catches repeats (log any that slip through).
  - Status: live. [ex-tales-forge #87](https://github.com/whyse-ab/ex-tales-forge/pull/87) merged 2026-10-09 with Fredrik's OK (`bda5e9e`); deployed with final main `dd5dc7e` (prod v84, playtest v75). Measured in the [full batch 2026-10-09](#2026-10-09-fresh-full-playtest-batch-as-the-new-baseline).
- **Why:** the banned "wipes her hands" still appeared in 57% of runs, and new tics replaced the banned ones ("leans an elbow" 11, "leans a hip" 10, Cobb "shifts his weight" 12).
- **Details:** [Analysis: Jev post-rework 2026-10-08](analysis-jev-post-rework-2026-10-08.md)

## 2026-10-08: The forge and Maude's cottage pull players in through rumours and hooks

- **Decision (Fredrik, via Case):** the forge and Maude's cottage pull players in through rumours and hooks from Brenna and the regulars, tied to what the world is doing, so the lore actually gets found.
  - Status: live. [ex-tales-forge #88](https://github.com/whyse-ab/ex-tales-forge/pull/88) merged 2026-10-09 with Fredrik's OK (`77ba4e2`); deployed with final main `dd5dc7e` (prod v84, playtest v75). Measured in the [full batch 2026-10-09](#2026-10-09-fresh-full-playtest-batch-as-the-new-baseline).
- **Why:** the forge, Maude's cottage and the lore were never reached in 23 runs.
- **Details:** [Analysis: Jev post-rework 2026-10-08](analysis-jev-post-rework-2026-10-08.md)

## 2026-10-08: Clarification: the safety read is part of the intent call, not a separate Jev call

- **Clarification (Fredrik, via Case, 07:27):** "We don't need another call to Jev, we just need to add it to the existing intent call." The rule of [the GM gets the player's own words when the safety read is confident](#2026-10-08-the-gm-gets-the-players-own-words-when-the-safety-read-is-confident) stands (threshold 0.90, fallback to the intent summary, logged). What changes is how the safety read is done: it is two more fields in the Tier 1 intent call's reply, `input_safety` (`benign`, `jailbreak`, `prompt_injection`, `nefarious`) and `input_safety_confidence`. The instructions sit in the static intent system prompt, so prompt caching still works. The separate Jev call (purpose `input_safety`) and its TypeSafe key are gone. That entry is unchanged otherwise.
- **The heuristic path has no safety read.** Most turns never make the intent call, because the heuristic reads them alone.
  - On playtest, 14 of 258 player messages on 2026-10-08 went to the intent call (5%), and 0 of 714 on 2026-10-07; the rest were heuristic.
  - Those turns now get a short typed summary of the action (`speak (target: innkeep)`) instead of the player's words. That is the simplest safe choice: no extra calls and no unchecked text. Its cost is that on about 95% of turns the GM no longer sees what the player said this turn.
  - `INTENT_CALL_EVERY_TURN=on` sends every default-variant turn through the intent call instead. Every turn then gets a safety read and can quote the player. The cost is one intent call per heuristic turn, about $0.0024 and 2.0 s at the median (3.5 s at p90) on the player's clock, and the LLM's reading replaces the heuristic's. Default off; **Fredrik decides** (a playtest comparison with the flag on and off is the natural test).
- **Cost of the extra fields** (6 sample messages, the same intent call before and after):
  - About +260 input tokens and +28 output tokens per intent call, about +$0.0004 (+21%) and +0.25 s.
  - Averaged over all turns at today's 5% intent share, that is about +$0.00002 and +15 ms per turn compared with before PR #76.
  - All six were labelled as expected: three benign (0.90–0.95), two `prompt_injection` (0.95) and the DAN text `jailbreak` (0.95).
- **Caveats:**
  - **The confidence is the LLM's own estimate.** For ordinary play it was 0.90 or 0.95, so the 0.90 threshold sits at the edge.
  - **Earlier turns still reach the GM unchecked.** The GM's per-turn prompt lists earlier turns' raw player text under "Recent turns" (up to 120 characters each), with no safety read; this PR does not change that. Gating that list on each turn's decision would be a follow-up.
- **Logged and queryable:** each decision goes in `ai_calls.meta` (`label`, `confidence`, `threshold`, `used`, `reason`). It is stored on the intent call's row (purpose `intent`) and on the turn's `turn.intent` step row, which exists for every message, so heuristic turns count too (reason `no_intent_call_heuristic`). `/admin/costs` shows the per-turn fallback rate. In SQL:

    ```sql
    SELECT count(*) FILTER (WHERE meta->>'used' = 'summary')::float / NULLIF(count(*), 0) AS fallback_rate,
           count(*) AS turns
    FROM ai_calls
    WHERE purpose = 'turn.intent' AND meta IS NOT NULL
      AND inserted_at > now() - interval '7 days';
    ```

- **Status:** [ex-tales-forge #76](https://github.com/whyse-ab/ex-tales-forge/pull/76), reworked; not merged or deployed. Merging needs Fredrik's OK, after the baseline/default comparison. The baseline variant keeps its intent prompt and schema (frozen).

## 2026-10-08: The GM gets the player's own words when the safety read is confident

- **Decision (Fredrik, via Case):** the GM gets the **player's own words** as the quote in the `PlayerAction` (`overall_intent`), sanitised and at most 500 characters, on **both** intent paths (heuristic and intent LLM), when an input safety read is **at least 90% confident the message is benign**: not a jailbreak, not prompt injection, not nefarious, so the risk is near 0. Below that, the GM gets the intent summary, and the fallback is logged.
- **Supersedes:** [Clarification: the GM gets a typed struct plus a short quote of the player's words](#2026-10-08-clarification-the-gm-gets-a-typed-struct-plus-a-short-quote-of-the-players-words). There, the intent LLM's summary was the quote whenever the intent LLM read the turn, and the heuristic path always quoted the player's text unchecked. That entry is unchanged otherwise. The validated, typed `PlayerAction` still decides what happens, and the server's rules still read it.
- **How** ([ex-tales-forge #76](https://github.com/whyse-ab/ex-tales-forge/pull/76), stacked on #75, not merged or deployed; merge needs Fredrik's OK, after the baseline/default comparison):
  - **The call:** one Jev call per turn (`TalesForge.Game.PlayerQuote`, call type `jev`, purpose `input_safety`, `jev-1.13.0`). It is a choice between fixed labels, `benign`, `jailbreak`, `prompt_injection` and `nefarious`, with a confidence. There was no input check to reuse; this call is new. Unstructured input and a typed answer make it a Jev call by the [call-type rule](call-types.md).
  - **The threshold:** `PLAYER_QUOTE_MIN_BENIGN_CONFIDENCE` (0..1, default 0.90), read in `config/runtime.exs`. A quote needs label `benign` and confidence ≥ threshold.
  - **The fallback:** another label, a lower confidence, an error, a 2 s timeout or no TypeSafe key all mean the summary. The summary is the intent LLM's summary, or a short typed summary such as `speak (target: innkeep)` when the heuristic read the turn.
  - **The key:** `TYPESAFE_INTENT_API_KEY` when set (staged on playtest), else `TYPESAFE_API_KEY`. Production has neither, so on production the GM gets the summary until a key is set (Fredrik's OK).
  - **Scope:** only the GM prompt's quote changes. The GM prompt template and the golden fixtures are unchanged. The baseline variant makes no read (frozen for the comparison).
  - **Parallel:** the read runs alongside the rules, prices and NPC reactions; the turn waits for it only before the GM prompt (step `turn.player_quote`).
- **Cost and latency** (measured 2026-10-08 on 10 sample messages):
  - About 510 input tokens per read, about **$0.00002 per turn**, under 1% of a GM call.
  - 73–323 ms, median about 130 ms, mostly hidden behind the NPC reaction call on playtest.
  - Ordinary play (including in-story fights and lies) read `benign` 1.00.
  - Injection attempts read `prompt_injection` 0.97–1.00. A DAN-style jailbreak read `prompt_injection` 0.41; it still falls back, because the label is not benign. A real-world weapon question read `nefarious` 0.96.
- **Logged and queryable:**
  - Each turn logs a `player quote … used=quote|summary reason=… label=… confidence=… threshold=…` line.
  - Each turn stores `label`, `confidence`, `benign_probability`, `threshold`, `used` and `reason` in `ai_calls.meta`.
  - `/admin/costs` shows the fallback rate ("GM quote fallback (input safety)"). In SQL:

    ```sql
    SELECT count(*) FILTER (WHERE meta->>'used' = 'summary')::float / NULLIF(count(*), 0) AS fallback_rate,
           count(*) AS reads
    FROM ai_calls
    WHERE purpose = 'input_safety' AND inserted_at > now() - interval '7 days';
    ```

- **Why:**
  - The player's own words keep their tone and detail better than a summary, which flattens them.
  - The safety read keeps text that tries to steer the GM, or that is not play, out of the prompt, for a fraction of a cent.
  - A summary is still the safe default whenever the read is unsure or unavailable.
- **Details:** [Fly secrets](fly-secrets.md) (`PLAYER_QUOTE_MIN_BENIGN_CONFIDENCE`, `TYPESAFE_INTENT_API_KEY`), [Call types](call-types.md)

## 2026-10-08: Clarification: nothing syncs from the earlier apps

- **Clarification (Fredrik, via Case):** ex-tales-forge stands on its own. Nothing is synced from text-forge, tales-forge-new or any other earlier app; its rules, prompts, packs and code are maintained in ex-tales-forge. The earlier apps are history only.
- **Applies to:** [the code docs stand alone](#2026-10-08-clarification-the-code-and-its-docs-stand-alone-where-the-code-came-from-is-recorded-here). Its notes on where the code came from are history, and the old "sync rules and prompts from text-forge" note it mentions does not apply any more. That entry is unchanged otherwise. The Agent Rules say the same ([ex-tales-forge #75](https://github.com/whyse-ab/ex-tales-forge/pull/75)).
- **Why:** one source of truth for the game's rules and prompts; the golden prompt tests guard them, and nobody has to watch another repo.

## 2026-10-08: Clarification: the GM gets a typed struct plus a short quote of the player's words

- **Clarification (Fredrik, via Case):** the GM gets the validated, typed `PlayerAction` **plus a short, sanitised quote of the player's words**, and that is intended. The quote is the action's `overall_intent`: at most 500 characters, with whitespace collapsed and "ignore previous instructions" phrases removed. When the heuristic reads the turn it is the player's own text; when the intent LLM reads it, it is that call's short summary of the message, sanitised the same way. The full raw message never reaches the GM.
- **Applies to:** [GM pipeline direction](#2026-10-07-gm-pipeline-direction) ("a typed struct with a short quote of the player's words"). That entry is unchanged. The Agent Rules used to say "raw player text never reaches Tier 2"; they now say this ([ex-tales-forge #75](https://github.com/whyse-ab/ex-tales-forge/pull/75)).
- **Why:** the quote lets the GM keep the player's tone, while the typed struct and the server's rules decide what happens.
- **Details:** `TalesForge.Game.Intent` (`sanitize_summary/1`), [Call types: target turn pipeline](call-types.md#target-turn-pipeline)

## 2026-10-08: The prose-only GM prototype is dropped; the GM has one structured reply mode

- **Decision (Fredrik, via Case):** the prose-only GM prototype (`GM_REPLY_MODE=prose`, [ex-tales-forge #38](https://github.com/whyse-ab/ex-tales-forge/pull/38)) is dropped and its PR closed without merging. The GM keeps **one reply mode**, the strict structured JSON schema, and there is no reply-mode flag. This answers the open question "Prose-only GM vs structured reply format" (bottom of this file).
- **Why:** in the prototype's local runs (Paul, Tin Valley, 5 turns, 2 runs per mode) prose was cheaper and faster: $0.00395 against $0.00567 per turn (−30%), median GM latency 4.0 s against 4.8 s, and first tokens at about 0.8 s when streamed. But it lost what the schema gives:
  - **NPC memories:** the GM wrote none, so NPCs only had automatic "Overheard player: …" lines and a later turn could contradict an earlier promise or price (one room-price contradiction in a prose run, none in the schema runs);
  - **lore anchoring:** invented facts were not recorded per turn (both final prose runs turned the orc nest into "harpies"; neither schema run reached the nest, so that sample can't compare the modes), and the summary updated only every 3 turns.
  - **No clear gain in play:** session scores showed no difference either way (Jev 4.14 prose against 4.01 schema, n = 4 against 5, with lower confidence for prose), and the schema stayed the default.
  - Since then the schema mode has the useful parts of the prototype: the Jev NPC reaction before the GM call (`NPC_REACTIONS`) and, with `WORLD_AGENTS` on, facts read from the narration after each turn.
- **Details:** [ex-tales-forge PR #38](https://github.com/whyse-ab/ex-tales-forge/pull/38) (results and trade-offs), [Analysis: Jev scores 2026-10-07](analysis-jev-scores-2026-10-07.md), [Design: world agents](design-world-agents.md)

## 2026-10-08: Clarification: the code and its docs stand alone; where the code came from is recorded here

- **Clarification (Fredrik, via Case):** ex-tales-forge's code, module docs, comments, README and Agent Rules (`AGENTS.md`, the "Agent Rules" page of `/admin/code-docs`) describe what the code does now. They no longer mention the earlier apps; history and origin notes live in this repo. Nothing about the game changes.
  - Status: [ex-tales-forge #75](https://github.com/whyse-ab/ex-tales-forge/pull/75) is approved by Fredrik (2026-10-08) and is merged after the current playtest series ends; not merged or deployed yet. It removes 18 such references in 9 files.
- **Where the code came from** (the notes removed from ex-tales-forge, kept here):
  - **text-forge** (FastAPI + Next.js, file-based campaigns with a git commit per campaign turn; repo `text-forge`, still under `fpahlen`, see [Infrastructure](infrastructure.md)). ex-tales-forge started as an Elixir rewrite of it. Its `backend/app/rules/*.md` became `priv/rules/*.md`, its `backend/app/prompts/*.txt` became `priv/prompts/*.txt`, and the Crossroads NPC files `priv/npcs/*.json`, the server-side dice and Learning Points (`Game.Mechanics`) and the play-test skill (`.grok/skills/play-test`) came from it. Its Supabase code was not ported. Turn history moved from git commits to the `Turn` table (same goal, different storage). The old Agent Rules also said "when rules or prompts change in text-forge, sync the corresponding files here"; that note is gone with the rest.
  - **tales-forge-new** (`fpahlen/tales-forge-new-31993d9d`, the React + Supabase app; tales-forge.ai on Netlify, see [Infrastructure: to retire](infrastructure.md#to-retire)). The skill rules in `priv/characters/creation.json` come from its written rules (sources listed in [character creation port: skill rules](character-creation-port.md#skill-rules-ported-2026-10-07)), and the prompt-prefix test (`test/ex_tales_forge/game/prompt_prefix_test.exs`) was ported from its `_shared/__tests__/promptOrdering.test.ts`.
  - Left in the code on purpose: the "Starting Wealth (Legacy Fallback)" / `STARTING_WEALTH` text in `priv/rules/economy.md` and its pack copies. It is part of the GM's rules text and the golden prompt fixtures, which must not change by accident.
- **Why:** humans and coding bots read the module docs to learn what the code does. Notes about another app's files send them to code they don't have and make the docs go stale; one place for history keeps both clear.
- **Details:** [ex-tales-forge PR #75](https://github.com/whyse-ab/ex-tales-forge/pull/75), [Coding standards](coding-standards.md), [character creation port](character-creation-port.md)

## 2026-10-07: Build out the inn and its surroundings for every player type; record scene changes

- **Decision (Fredrik, via Case):**
  - Build out the inn and its surroundings so **every player type finds a favourite activity**: talking, trading, exploring, sneaking, fighting, lore, crafts and so on. This is done through **world agents and locations**, not a longer script.
  - Fix the **leave-the-inn bug**: when the player leaves, record the **scene change** (new location and the NPCs present there), so the GM stops describing the inn and stops answering as Brenna after the player has gone.
  - Status: merged 2026-10-08: [ex-tales-forge #68](https://github.com/whyse-ab/ex-tales-forge/pull/68) (scene changes) as `7b88dad` and [#72](https://github.com/whyse-ab/ex-tales-forge/pull/72) (inn world) as `9080cb1`; deployed (prod v67 and v69, playtest v56 and v58). `INN_WORLD` is on for playtest only.
- **Why:** in 62% of runs the player tries to leave the inn, and after 38 of 65 such attempts the GM is still describing the inn or Brenna on the next turn. In Paul's two weakest runs the GM walks him to the Market Square and then answers his speech to Osric as Brenna, back at the bar; neither run registered a scene change. With only the inn to play in, each persona runs out of things it likes (Hawk gets chores, Lars's adventure is deferred).
- **Details:** [Analysis: Jev baseline 2026-10-07, §4 and recommendation 1](analysis-jev-baseline-2026-10-07.md), [Design: world agents](design-world-agents.md), [PR #68](https://github.com/whyse-ab/ex-tales-forge/pull/68) (scene changes), [PR #72](https://github.com/whyse-ab/ex-tales-forge/pull/72) (inn world, `INN_WORLD`)

## 2026-10-07: Hawk gets real conflict: a minor antagonist who acts on their own

- **Decision (Fredrik, via Case):** Hawk gets real conflict. A **minor antagonist** stirs up trouble in or near the village and **acts on their own**, whether or not the player engages. This follows the living-world and factions direction: an agent with a goal and a plan that moves on world time. It is **not a scripted fight**.
  - This builds on [To try: living world](#2026-10-07-to-try-living-world) and makes a small first case of it a decision for Tin Valley.
  - Status: merged 2026-10-08: [ex-tales-forge #73](https://github.com/whyse-ab/ex-tales-forge/pull/73) (Tinjacks) as `9e7d447` and [#71](https://github.com/whyse-ab/ex-tales-forge/pull/71) (fights roll) as `8bf10d3`; deployed (prod v70 and v66, playtest v59 and v55). `WORLD_ANTAGONIST` is on for playtest only.
- **Why:** Hawk almost never meets danger. His turn mean is 1.93, only 4 of 13 runs reach a turn scoring 3 or more (never before turn 8), and his session score is 2.54 without a fight roll against 4.61 with one. Brenna's "lend a hand" hooks have him hauling kegs. A scripted fight would fix the number once; an antagonist who moves on their own gives danger that the player's choices change.
- **Details:** [Analysis: Jev baseline 2026-10-07, §1, §4 and recommendations 2–3](analysis-jev-baseline-2026-10-07.md), [Design: world agents, living world](design-world-agents.md#living-world-design-to-try), [PR #73](https://github.com/whyse-ab/ex-tales-forge/pull/73) (Tinjacks antagonist, `WORLD_ANTAGONIST`), [PR #71](https://github.com/whyse-ab/ex-tales-forge/pull/71) (fights roll)

## 2026-10-07: Skill growth: spend 1 LP for one improvement attempt (supersedes the tiered thresholds)

- **Decision (Fredrik, via Case):** a new skill growth rule.
  - Spending **1 LP buys one improvement attempt** on that skill.
  - Roll **d20**. If the result is **equal to or higher than the current skill level**, the skill gains **+1**.
  - More LP means more attempts.
  - This **supersedes** the progression part of [Skill rules ported from the old game](#2026-10-07-skill-rules-ported-from-the-old-game-signature-skills-up-to-7-growth-no-longer-stalls) ([#64](https://github.com/whyse-ab/ex-tales-forge/pull/64)): the 5 / 7 / 10 / 15 LP tier thresholds, the failure requirement, the rest requirement and the tiered thresholds are gone. It also supersedes item 4 ("growth pace stays as it is for now") of [Skill rules: the open questions answered](#2026-10-07-skill-rules-the-open-questions-answered). LP are still earned per roll as before, including the stat bonus.
  - Status: merged 2026-10-08 as `c2f237f` ([ex-tales-forge #67](https://github.com/whyse-ab/ex-tales-forge/pull/67)); deployed (prod v65, playtest v54). In it: attempts happen at the end of every turn (every whole LP is spent), a trainer gives one free attempt at +5, and the Expert −3 / Master −5 modifiers are removed. The `baseline` variant keeps the #64 rule.
- **Why:** skill growth has stopped. The baseline averages about 1.0 LP per run, and there were **0 improvement attempts in 65 runs**: an attempt needed 5 LP, a failure and a rest of an hour, and almost no run had all three. With one attempt per LP, every LP is a visible chance to grow, and the d20 ≥ level roll slows growth naturally as a skill gets higher (a success chance of (21 − level)/20).
- **Details:** [Analysis: Jev baseline 2026-10-07, §6 and recommendation 7](analysis-jev-baseline-2026-10-07.md), [character creation port: growth rule replaced](character-creation-port.md#growth-rule-replaced-2026-10-07-1-lp--one-improvement-attempt), [PR #67](https://github.com/whyse-ab/ex-tales-forge/pull/67)

## 2026-10-07: How the GM plays Brenna: no default echo, no stock tics

- **Decision (Fredrik, via Case):**
  - The GM does **not** echo or restate the player's line by default. It answers the action instead of re-narrating it.
  - Echoing the player's last few words is allowed only as a **deliberate, rare negotiator move** by a character, to draw the player out ("…the old shaft?"). It is never a turn opener by habit.
  - Brenna's "on the house" generosity default goes. A freebie needs a reason in the story.
  - The stock gesture "tilts her head (toward)" goes, along with the other new tics the baseline found.
  - This refines the prose rules in [Brenna is a warm, chatty barkeep](#2026-10-07-brenna-is-a-warm-chatty-barkeep-a-lead-by-turn-2-gm-prose-cleanup): "no echoing the player's words" stays, and the rare deliberate echo is now the one exception. Brenna stays warm and chatty.
  - Status: merged 2026-10-08 as `eb752fa` ([ex-tales-forge #70](https://github.com/whyse-ab/ex-tales-forge/pull/70)); deployed (prod v68, playtest v57).
    - Default variant only: "React, do not restate", the deliberate-echo exception, a banned stock-phrase list (now also "wipes her hands", which replaced the old tics in local checks), "a gesture in the recent turns is used up", and NPCs charge their prices.
    - Brenna's personality: "her gossip is free; her goods are not".
    - The default golden fixtures were regenerated on purpose. The baseline variant and its fixtures are unchanged.
    - Local checks (6 small runs, not comparable to Fly): the GM echoed the player's line on 1 of 36 turns, against 22% in the baseline.
    - It conflicts with #68 in `scene_system.txt` and the fixtures. Whichever merges second needs a rebase.
- **Why:** the GM opens 22% of turns by repeating the player's own line (Lotta: 52%; Elara runs: 5%). Brenna gives something "on the house" in 77% of runs and "tilts her head toward" in 36 of 65 runs. The cold "eyes narrow" tic has been replaced by a generous one, which is also what confuses Ronny's rubric.
- **Details:** [Analysis: Jev baseline 2026-10-07, §4 and recommendations 4–5](analysis-jev-baseline-2026-10-07.md)

## 2026-10-07: A stricter Jev rubric before the next A/B; the personas stay as they are

- **Decision (Case's recommendation; Fredrik did not object):** before the next A/B, the Jev rubric gets stricter at the top. The top levels need concrete evidence in the transcript, such as a surprise, a consequence that matters, a callback to earlier play, or an NPC acting on its own, so that a pleasant but uneventful session no longer reaches them. The rubric version or hash is bumped. Any comparison with the 2026-10-07 baseline must re-score the baseline with the new rubric. The personas (Paul, Lotta and the others) do **not** change: they model real players, so the scale has to move, not the players.
  - This refines [Jev persona-affect scoring](#2026-10-07-jev-persona-affect-scoring): same 1–5 scale and same inputs, with harder top levels.
  - Status: merged 2026-10-08 as `cb6a5f6` ([ex-tales-forge #69](https://github.com/whyse-ab/ex-tales-forge/pull/69)); deployed (prod v64, playtest v53).
    - Paul is now `jev-affect-v1-fd84ebb` (was `dfec71a`) and Lotta `jev-affect-v1-ce84a1a` (was `4545d3b`). Lars, Hawk and Ronny are unchanged.
    - Level 3 now covers smooth but generic play. Level 4 needs a reply to their particular character. Level 5 needs evidence of at least two of: a surprise, a consequence, a callback, an NPC acting on its own goals (Lotta: or care when stakes hurt).
    - Pilot re-score of the 26 baseline runs: Paul's turns went from argmax 5 on 124/130 to 4 on 75 and 5 on 54. Lotta's went from 4 on 130/130 to 3/4/5 on 24/94/12.
    - Paul's session mean did not drop (4.67 → 4.73), so for Paul use turn means. See [Jev scoring](jev-scoring.md#stricter-top-for-paul-and-lotta-2026-10-07).
- **Why:** Paul and Lotta sit at the ceiling. Lotta's most likely level is 4 on 130 of 130 turns (session SD 0.07), and Paul's is 5 on 124 of 130. At that point no change to the game can show up in their scores, so they are useless as A/B signals.
- **Details:** [Analysis: Jev baseline 2026-10-07, §1 and recommendation 6](analysis-jev-baseline-2026-10-07.md), [Jev scoring](jev-scoring.md)

## 2026-10-07: Skill rules: the open questions answered

- **Decision (Fredrik, via Case):**
  1. **Half-Elf** keeps the game's DEX +1, CHA +1 (not the old JSON's CHA +1, INT +1). No change.
  2. **The untrained floor applies only to skills at level 0.** As in the old rule ("an untrained attempt uses stat ÷ 3"), a level-0 skill rolls against `max(stat ÷ 3, stat bonus)`. A trained skill uses level + stat bonus as before, so levels 1–3 always count. The roll note says "untrained: stat ÷ 3". Done in [ex-tales-forge #62](https://github.com/whyse-ab/ex-tales-forge/pull/62).
  3. **The past occupation feeds the OCEAN, Maslow and concerns defaults** for player characters, as occupations do for NPCs. Fredrik's earlier decision is that defaults come from class, race, social standing and occupation. It replaces "adventurer" there too (now only a fallback). Done in [#63](https://github.com/whyse-ab/ex-tales-forge/pull/63). The occupation goes on the GM's character sheet with the planned "GM sees who the character is" PR (character-creation PR 5). Today that sheet has no race, class or skills either, so adding the occupation alone would be a separate prompt change ahead of the PR that adds the whole character section once.
  4. **Growth pace stays as it is for now.** Every playtest run now records its skill growth: rolls, LP gained, improvement attempts and improvements per skill, on the run's `growth`. That way the baseline shows how fast characters grow.
- **Why:** these close the open questions from the skill-rules port before Fredrik merges it.
- **Details:** [character creation port: skill rules](character-creation-port.md#skill-rules-ported-2026-10-07)

## 2026-10-07: Skill rules ported from the old game; signature skills up to 7; growth no longer stalls

- **Decision (from Fredrik, via Case):** player characters get the written skill rules of the old game. Signature skills are Fredrik's call.
  - **Skill budget 25:** levels 1–3 cost 1 each and levels 4–5 cost 2 each. The normal cap is 5, and a character needs at least 5 skills. The screen suggests a spread build, and the player can change it within the budget.
  - **Signature skills (Fredrik's call):** one or two skills may go to **7** for solo heroes. Levels 6–7 cost **3 each**, continuing the 1, 1, 1, 2, 2 curve: a 7 bought from scratch costs 13 of the 25 points, a real commitment.
  - **Free levels:**
    - the class package gives all three class skills at 3/2/1 (before, the third was dropped);
    - a **past occupation**, chosen from the existing occupation tables, gives +2 on its core skills and +1 on its secondary ones. It replaces the skill-less "adventurer", and each class suggests one;
    - race: Human +5 and Half-Elf +3 points, Elf/Dwarf/Gnome/Halfling fixed skill levels from `game-system.json`.
  - All free levels stack under the same caps, and levels the caps cut off come back as points.
  - **Untrained floor:** a roll never uses less than `max(stat ÷ 3, stat bonus)`.
  - **Progression:**
    - LP thresholds by tier: 5 / 7 / 10 / 15 (Novice, Adept, Expert, Master);
    - improvement roll modifiers: Expert −3, Master −5;
    - LP stat bonus: `(stat − 10) ÷ 4`, 0 to +2 per roll;
    - **one** failure since the last attempt is enough (was three).
  - Status: open PRs, not merged or deployed. Each waits for Fredrik's approval:
    - [ex-tales-forge #62](https://github.com/whyse-ab/ex-tales-forge/pull/62): rules engine and untrained floor;
    - [#63](https://github.com/whyse-ab/ex-tales-forge/pull/63): occupation;
    - [#64](https://github.com/whyse-ab/ex-tales-forge/pull/64): progression, with the GM rules text and golden fixtures updated on purpose;
    - [#65](https://github.com/whyse-ab/ex-tales-forge/pull/65): creation screen and persona builds.
- **Why:** a solo character has no party to cover its gaps, so it must be well rounded from the start. The old cap of 2 class skills left created characters with two skills. After the roll rule ([#56](https://github.com/whyse-ab/ex-tales-forge/pull/56)) fewer actions roll at all, so "5 LP and 3 failures" would have stalled growth.
- **Details:** [character creation port: skill rules](character-creation-port.md#skill-rules-ported-2026-10-07), including every ambiguity in the old rules and how it was resolved; [persona characters](playtest-persona-characters.md)

## 2026-10-07: Brenna is a warm, chatty barkeep; a lead by turn 2; GM prose cleanup

- **Decision (Fredrik's call, via Case):** Brenna, the Tin Valley innkeep, becomes a warm, chatty barkeep who genuinely enjoys running the tavern.
  - Her OCEAN traits go up on extraversion and agreeableness: O4 C8 E5 A6 N5 → **O6 C7 E8 A8 N3**. Her mood is cheerful. Her concern becomes "keep the common room full, warm and talking, and her regulars safe while the hills are restless" (Maslow is still belonging).
  - Her default brush-off is dropped. She treats a civil, paying guest warmly unless the character gives her a reason not to.
  - The story gets moving by turn 2. NPCs can carry ready-made `hooks` (Brenna has four: Osric Vane paying for steel against the orc nest, Caldern Voss and the shaft, goods the orcs took off the valley road, and a free meal plus gossip for a helper). The GM prompt asks for one concrete lead (a job, a name or a place) by the end of the player's second turn at the latest.
  - The GM's prose is cleaned up:
    - always second person, so no "Elara …" openers;
    - no echoing the player's words;
    - no re-serving or re-describing;
    - stock phrases ("eyes narrow", "scarred oak", "slides the mug across", "the hearth crackles") are named and avoided;
    - prices, names and promises stay consistent.
  - The old Brenna and the old prompts stay available as the opt-in `baseline` behaviour variant, so the rework can be A/B-tested on one deploy.
  - Status: [ex-tales-forge PR #58](https://github.com/whyse-ab/ex-tales-forge/pull/58) is open, stacked on #56, and waits for Fredrik's approval. It is not merged or deployed.
- **Why:** in the Jev analysis, Brenna's brush-off ("eyes narrow", flat voice, "clearly done") appeared in 39 of 44 runs. It was the most common cause of low turn scores (15 of the 19 lowest turns examined), hit Lotta hardest, and no run got past the inn in five turns.
- **Details:** [Analysis: Jev scores 2026-10-07](analysis-jev-scores-2026-10-07.md), [PR #58](https://github.com/whyse-ab/ex-tales-forge/pull/58), [measurement plan](plan-jev-baseline-and-ab.md)

## 2026-10-07: No skill roll on ordinary talk; a failed roll only means you learn nothing extra

- **Decision (from Fredrik, via Case):**
  - Ordinary talk and everyday actions (ordering, chatting, asking a question, looking around) get **no skill roll**. A check happens only when the outcome is genuinely uncertain and failing would cost something.
  - A **failed** roll costs only what was tried for. A failed read, search or recall means the character learns nothing extra; it never makes an NPC colder, more suspicious or hostile.
  - NPC attitude follows the character's words and deeds, not the dice. People notice an attempt only when the action itself shows (a lie, a threat, a clumsy grab).
  - The fix is at the root, in three places:
    - the intent heuristic no longer falls back to Insight (72% of rolls were Insight);
    - intent no longer forces a skill onto every action;
    - action resolution no longer defaults to a check.
  - In addition, the intent and GM prompts state the rule, and unseen checks (Insight, history and similar) no longer reach NPC reactions.
  - The old behaviour is kept as the opt-in `baseline` behaviour variant (`variant: "baseline"`) for A/B runs.
  - Status: [ex-tales-forge PR #56](https://github.com/whyse-ab/ex-tales-forge/pull/56) is open and waits for Fredrik's approval. It is not merged or deployed.
- **Why:** in the Jev analysis, the rules engine rolled Insight on 72% of turns (155 of 216), even for ordering ale, and those checks failed about 70% of the time.
  - The GM then narrated each failure as the NPC turning colder: 87% of failed turns had cold phrasing.
  - Within a run, a failed check cost about −0.35 on the turn score, and 9 of the 10 lowest non-Hawk turns were failed checks.
  - In short, the dice punished players for talking.
- **Details:** [Analysis: Jev scores 2026-10-07](analysis-jev-scores-2026-10-07.md), [PR #56](https://github.com/whyse-ab/ex-tales-forge/pull/56)

## 2026-10-07: GitHub team sign-in is the only login on production and playtest

- **Decision (from Fredrik, via Case):** "Sign in with GitHub", checked against the GitHub team `whyse-ab/tales-forge` (`ADMIN_GITHUB_TEAM`), is the only login on production (`tales-forge`) and playtest (`tales-forge-playtest`) for now.
  - Email magic-link sign-in is disabled: its routes, the email form and the code that sent the links are gone, and old email-only sessions no longer count. The `ADMIN_EMAILS` allowlist no longer lets anyone in.
  - Every page and LiveView needs a signed-in team member: play, character creation (and any route added later), admin, costs, code docs at `/admin/code-docs`, and playtest run reports. Only the login page, the GitHub OAuth request and callback, and the health check (`/health`; the Fly checks move off `/`) are open, plus the static files the login page needs and the token-guarded machine-to-machine `/internal/costs`. Anyone else is sent to the login page. A GitHub user who isn't on the team is refused there with a short message.
  - No separate admin login: any signed-in team member gets the admin pages, with no extra admin check or second login step. The team check is the single gate.
  - Status: [ex-tales-forge PR #54](https://github.com/whyse-ab/ex-tales-forge/pull/54) is open and waits for Fredrik's approval. It is not merged or deployed, so this takes effect when it is.
- **Why:** both apps were publicly reachable, and Fredrik doesn't want that. No unauthenticated route, LiveView event or endpoint may start an AI call. The AI entry-point audit is in the PR.
- **Supersedes:** [2026-10-06: Sign-in](#2026-10-06-sign-in) (admin uses email magic links, logins last 30 days). Logins still last up to 30 days, with team membership rechecked on every request.
- **Details:** [ex-tales-forge PR #54](https://github.com/whyse-ab/ex-tales-forge/pull/54), [GitHub sign-in](infrastructure.md#github-sign-in-for-the-admin), [Fly secrets](fly-secrets.md)

## 2026-10-07: Clarification: the Tuckman phase belongs to the group, not the character

- **Clarification (from Fredrik, via Case):** the Tuckman phases (forming, storming, norming, performing, adjourning) are a property of a team or group (party, gang, council), not a character attribute.
  - A Character references its group membership(s), and the phase lives on the Group.
  - Wherever a character's behaviour depends on the phase, the phase is read from the group. That includes the companion rule ("decide by their reaction, concerns and party phase").
- **Applies to:** the [2026-10-07 seven design answers](#2026-10-07-one-character-entity-the-seven-design-answers). In answer 4 (companions), "party phase" means the phase of the companion's party group. In the "Why", Tuckman is listed among the levers, but it is the group's lever, not one each character holds. That entry is unchanged otherwise.
- **Why:** a phase describes how a group works together. Storing it per character would let members disagree about their own group's phase and would need syncing on every group event.
- **Details:** [World agents: character levers](design-world-agents.md#character-levers-design-not-built), [Plan: one Character entity, section 3](plan-unify-character.md#3-levers-mapped-onto-character). The code has no Tuckman or phase field on characters (checked on ex-tales-forge `main`, `e867f16`).

## 2026-10-07: Characters: defaults, rescale, backfill and double-write (#50, #51)

- **Decision:** approved by Fredrik on 2026-10-07 at 15:49: "Yes, merge #50 and #51, deploy, and run the backfill on prod and playtest".
  - [#50](https://github.com/whyse-ab/ex-tales-forge/pull/50) (merge `8d8efc3`, production v47, playtest v35): `Characters.Defaults` (a global label list extended per pack, seeded per-character variation, validated overrides) and NPC skills on the PC scale.
  - [#51](https://github.com/whyse-ab/ex-tales-forge/pull/51) (merge `e867f16`, production v48, playtest v36): backfill of existing sessions, and a double-write of the `characters` rows after every turn.
  - The release migrate step passed on both apps. Nothing reads `characters` yet.
- **Backfill (2026-10-07, about 15:58):**

| App | Before | Run 1 | Run 2 | After |
|---|---|---|---|---|
| Production | 0 characters, 0 memories (5 sessions, 15 `npc_instances`) | inserted 20, memories 3, failed none | inserted 0 | 20 (5 PC + 15 NPC), 3 memories |
| Playtest | 8 characters (2 PC + 6 NPC), 0 memories (22 sessions, 63 `npc_instances`, 18 playtest runs) | inserted 77, memories 141, failed none | inserted 0 | 85 (22 PC + 63 NPC), 141 memories |

  - Every playtest-run PC has controller `bot` with the run's persona as its reference: paul 13, lotta 2, hawk 1, lars 1, ronny 1. The other 4 playtest PCs and all 5 production PCs are `player`.
- **Check run:** Paul on playtest, 5 turns, Tin Valley.
  - The rows were updated after each turn: memory rows landed with turns 2–5, and the PC's learning points moved.
  - The new session's NPCs have the rescaled skills (innkeep persuasion 8, insight 8, etiquette 4).
  - No double-write errors in the logs.
  - Jev session affect 4.28 (confidence 0.63).
  - Game cost $0.0402 ($0.0080/turn; GM alone $0.0293), cache hits 4/4. Persona cost $0.0082 is logged separately.
- **Why:**
  - It completes phase 1: every PC and NPC now has a `characters` row that stays in step with play. That is the precondition for phase 2 (the read switch).
  - The rescale gives NPCs and PCs one skill scale without hand re-authoring.
- **Known gaps:**
  - The double-write runs after the turn, so an NPC change made outside a turn, or a memory written late in a turn, lands at the next turn.
  - Levers and OCEAN are set only when a row is first created.
  - Existing sessions keep their old NPC skill values.
- **Details:** [Plan: one Character entity, phased rollout](plan-unify-character.md#5-phased-rollout)

## 2026-10-07: Character defaults: the four answers

- **Decision:** confirmed by Fredrik on 2026-10-07 (via Case).
  1. **Label lists:** a global base list that each world pack extends.
  2. **Jev threshold:** confidence 0.6 to start. Every confidence is logged, and the threshold is tuned after playtests.
  3. **Variation:** small random variation, seeded per character (a hash of the session id plus the character key), so a character is stable on reload.
  4. **Player edits:** the player can edit everything Jev fills in, within the rules: stats within the point budget, OCEAN, concerns, background and name. This follows the per-section "own input or AI assist" flow.
- **Why:**
  - A shared base list keeps labels, tests and Jev questions consistent, while each world can still add its own occupations.
  - 0.6 is a cautious start that real playtest data can move.
  - Seeded variation stops two innkeepers from being clones without making a character change between page loads.
  - Player edits keep Jev as a helper, not a judge: 4 of 5 personas wanted per-section control.
- **Details:** [Plan: one Character entity, section 7.4](plan-unify-character.md#74-decisions-confirmed-by-fredrik-2026-10-07), [Plan: character creation port](character-creation-port.md#update-2026-10-07-derived-defaults-and-jev-direction-from-fredrik-via-case)

## 2026-10-07: Design direction: derived character defaults, and Jev for descriptions

- **Direction (from Fredrik, via Case):**
  - **Defaults:** stats, skills, OCEAN, Maslow level and concerns are derived in pure Elixir from class, race, social standing and occupation. The assumption is that people are reasonably skilled at their job and have a typical personality for the role.
  - **Notable characters** (the reluctant king, the sour barkeep) are hand-authored overrides on top of the defaults.
  - **Descriptions:** turning a free-text description into a Character is one Jev call (unstructured in, structured out). The same call serves player character creation: the player describes their character, Jev returns fixed labels with confidence, and the defaults fill the gaps.
- **Why:**
  - Most characters come out right with no authoring and no LLM.
  - Authors spend their time only on the characters that matter.
  - One skill scale falls out of occupation tiers, which is decision 5 without hand re-authoring.
  - Creation is fast and cheap (one Jev call, under $0.001) and keeps working when Jev is unsure or down.
  - It follows the call-types rule: structured answers from Jev and Elixir, not from an LLM.
- **Not yet decided:**
  - the label lists (per world or global);
  - the confidence threshold;
  - jitter;
  - what a player may edit;
  - whether a prose LLM call stays for the backstory.

  The derivation module lands with the skill-rescale PR. Jev for players lands with the character creation port, after phase 2.
- **Details:** [Plan: one Character entity, section 7](plan-unify-character.md#7-defaults-from-class-race-standing-and-occupation-jev-for-descriptions), [Plan: character creation port](character-creation-port.md#update-2026-10-07-derived-defaults-and-jev-direction-from-fredrik-via-case)

## 2026-10-07: Characters phase 1 merged and deployed (#48)

- **Decision:** ex-tales-forge PR #48 is merged (main `326c8ae`) and deployed: production v45, playtest v33. Approved by Fredrik ("Yes, merge #48 and deploy").
  - New tables `characters` and `character_memories`.
  - New sessions write one character per PC and NPC; nothing reads them yet.
  - Every pack NPC and PC file has `maslow` and `concerns`, checked at load time.
  - Elara now lives in the packs.
- **Why:** this is the setup step of the [Character plan](plan-unify-character.md), and it carries no behaviour change. A golden test keeps the GM prompts byte-identical.
- **Checked after deploy:**
  - Both release_command migrations passed, and both tables exist.
  - `/` returns 200, and logged-out admin pages redirect to login.
  - Packs and NPC files load with no validation errors.
  - A playtest Paul run completed 5 turns. It wrote 4 characters: Elara with controller `bot` (ref `paul`), plus 3 NPCs with controller `gm`.
  - Costs are logged: game $0.040, persona $0.0082 kept separate.
  - Logs show no app errors. The only health-check failure was during the restart.
- **Cost:** GM cost was $0.0081 per turn, back to the usual ~$0.008. The previous run's $0.0114 came from prompt-cache misses on turns 3 and 5 (2 of 4 later turns hit; this run 4 of 4). Each miss costs about $0.012 instead of $0.004–0.005. The 429 itself cost nothing: the failed call has no cost. Prompt size is the same in both runs (9,200–9,650 input tokens per GM call), so neither the prompt nor the token count changed.
- **Not yet:** backfill of older sessions, dual-write of per-turn changes, and the NPC skill rescale. These come in the next PR.
- **Details:** [ex-tales-forge PR #48](https://github.com/whyse-ab/ex-tales-forge/pull/48), [Plan: one Character entity](plan-unify-character.md)

## 2026-10-07: One Character entity: the seven design answers

- **Decision:** confirmed by Fredrik on 2026-10-07 (via Case). These are the answers to the open questions in the Character plan:
  1. **Scope:** characters are per session for now, but the schema is ready for a character to belong to a player and carry over (`owner_player_id`, `origin`). The persistent-world option (B) stays open in the design.
  2. **PC levers:** PCs get OCEAN, a Maslow level and concerns, visible on the character sheet.
  3. **AFK:** solo play pauses. In a party the GM takes over an absent PC after a timeout.
  4. **Companions** decide by their reaction, concerns and party phase, not by obeying.
  5. **Skill scale:** NPC skills are rescaled to the PC scale, and the trainer gap rule is re-checked.
  6. **Memory:** one shared events table (the existing `session_events`) plus per-character, personality-filtered memory rows.
  7. **Controller:** `player | gm | bot`. The persona runner uses `bot`.
- **Why:** with one shape for PCs and NPCs, every lever (OCEAN, Maslow, concerns, Tuckman, perception) works the same for everyone. Per session keeps phase 1 small and matches today's data, and the owner column means carry-over needs no second migration. One shared record of each event, with a personal memory of it per character, avoids copying facts while letting characters remember the same event differently. The `bot` controller keeps playtest data and costs apart from real players.
- **Details:** [Plan: one Character entity, section 6](plan-unify-character.md#6-decisions-confirmed-by-fredrik-2026-10-07)

## 2026-10-07: To try: living world

- **To try (not a final decision):** an unscripted world in which nothing waits for the player.
  - Factions and antagonists are agents with goals, plans, clocks, resources and a memory of who helped or hindered them.
  - A world tick (Oban cron, plus each turn's own ticks) advances their plans on world time, between sessions and during them. Most of the tick is Elixir functions.
  - Jev reacts for a faction when an event touches it.
  - The GM narrates only what a character perceives (direct encounters, news, rumours), following the perception rules.
  - Example: if nobody stops the Mining Guild, they dig too deep and something gets loose; if the player stops them, the Guild remembers and acts on it. Acting and not acting both have consequences.
  - Direction from Fredrik (via Case).
- **Why:** a world that moves on its own makes choices matter and gives emergent stories without scripting. Cost stays bounded: a world nobody visits costs well under $0.001 per world-day, and a played one adds a few tenths of a cent per day on top of the turns.
- **Depends on:** characters and world state that outlive one session (option B of Q1 in the Character plan). For now characters are per session but ready to belong to a player.
- **Details:** [Design: world agents, living world](design-world-agents.md#living-world-design-to-try), [Plan: one Character entity](plan-unify-character.md)

## 2026-10-07: Ash removal merged and deployed (#47)

- **Decision:** ex-tales-forge PR #47 is merged (main `a564e95`) and deployed: production v44, playtest v32. Ash, ash_postgres, ash_phoenix and igniter are gone, and the admin session and NPC forms use Ecto changesets. The NPC definition pages are read-only views of the pack files; Fredrik can veto this and get a small file-only editor back. The migration dropped the `adventures`, `locations` and `npc_definitions` tables. Approved by Fredrik ("Yes, merge #47 and deploy once the recount shows the tables are empty").
- **Why:** a recount right before the merge found all three tables empty on both apps. The release shrinks from 99.1 to 88.3 MB, and lib loses about 2,000 lines.
- **Checked after deploy:**
  - Both release_command migrations passed.
  - The three tables no longer exist.
  - `/` returns 200, and logged-out admin pages redirect to login.
  - As admin (in-machine request), the session form, NPC form and read-only definition page load.
  - A playtest Paul run completed 5 turns with costs logged: game $0.057, persona $0.0086 kept separate.
  - Logs show no app errors. One xAI 429 "at capacity" on a GM call was retried and succeeded.
- **Details:** [ex-tales-forge PR #47](https://github.com/whyse-ab/ex-tales-forge/pull/47), [Plan: remove Ash](plan-remove-ash.md)

## 2026-10-07: Ash removed for now; plain Ecto; revisit if an in-app adventure editor needs it

- **Decision:** ex-tales-forge drops Ash (`ash`, `ash_postgres`, `ash_phoenix`) and uses plain Ecto everywhere. The authoring layer (Adventure, Location, NpcDefinition and the pack importer) goes, the two admin edit forms move to Ecto changesets, and the three empty authoring tables are dropped. Revisit Ash if an in-app adventure editor needs it. Decided by Fredrik (via Case). **Supersedes the Ash part of "Elixir is the platform" below**; Phoenix LiveView, Oban and Jido stay.
- **Why:** only the authoring layer used Ash. Its three tables (`adventures`, `locations`, `npc_definitions`) are empty on prod and playtest, and the game reads its content from the pack files. The admin forms already have Ecto schemas underneath. Removing it cuts about 1,800 lines and about 11 MB of release, and leaves one data-access style for humans and bots to learn.
- **Details:** [Plan: remove Ash](plan-remove-ash.md), [Module audit](module-audit-2026-10-07.md). Done: merged and deployed as [#47](https://github.com/whyse-ab/ex-tales-forge/pull/47) (entry above).

## 2026-10-07: Code docs: ExDoc's JavaScript allowed past the admin CSRF check

- **Decision:** ex-tales-forge PR #45 is merged and deployed to production and playtest. Files served from the docs folder at `/admin/code-docs` skip Plug's cross-origin JavaScript check. The admin login check is unchanged. Approved by Fredrik ("Yes, open the fix PR, merge it and deploy once CI is green").
- **Why:** after #44 the pages loaded but every ExDoc script got 403, so the sidebar was empty and search didn't work. The files are static and hold no tokens. The session cookie is SameSite=Lax, so another site's `<script>` request has no admin session and is still redirected to login. The tests now run with CSRF protection on, which the test helpers turn off by default and which hid the bug.
- **Details:** [ex-tales-forge PR #45](https://github.com/whyse-ab/ex-tales-forge/pull/45), [PR #44](https://github.com/whyse-ab/ex-tales-forge/pull/44)

## 2026-10-07: Code docs served admin-only at /admin/code-docs

- **Decision:** ex-tales-forge PR #44 is merged and deployed to production and playtest. Each release builds the ExDoc site in the Docker builder stage (about 4 MB in the image, ex_doc itself stays out of the release) and serves it at `/admin/code-docs` behind the admin login, with a "Code docs" link in the admin nav. Approved by Fredrik ("Yes, merge #44 and deploy").
- **Why:** the documented code (see coding standards) should be readable where we already work, without a local build, and not public.
- **Details:** [ex-tales-forge PR #44](https://github.com/whyse-ab/ex-tales-forge/pull/44), [Coding standards](coding-standards.md)

## 2026-10-07: Coding standards: documented, typed, tested, enforced in CI

- **Decision:** every module has a `@moduledoc` and every public function a `@doc` (with doctests where sensible) and a `@spec` checked by Dialyzer. Credo strict, `mix format`, ExDoc for a browsable docs site, tests for every change with coverage tracked. CI enforces format, Credo, Dialyzer, tests with coverage and the docs build, so failing PRs can't merge. Existing modules are backfilled gradually, starting with the core GM, Character/Person and world-agent modules. Fredrik's standard, relayed by Case.
- **Why:** humans may need to understand the code one day, including code written by coding bots.
- **Details:** [Coding standards](coding-standards.md), [ex-tales-forge PR #43](https://github.com/whyse-ab/ex-tales-forge/pull/43)

## 2026-10-07: Merge the runner fix and world agents round 2, world agents still off

- **Decision:** ex-tales-forge PR #41 (the playtest runner ignores a stale "turn finished" message, which caused a double turn 2) and PR #42 (world agents round 2: prices from code and facts read from the narration) are merged and deployed. `WORLD_AGENTS` stays off in production and playtest; `NPC_REACTIONS` stays on in playtest only. Approved by Fredrik ("Merge #41 and #42 and deploy").
- **Why:** the runner fix makes playtest runs complete and comparable. Round 2 costs nothing while the flag is off, and having it on main lets the next round build on it.
- **Details:** [ex-tales-forge PR #41](https://github.com/whyse-ab/ex-tales-forge/pull/41), [PR #42](https://github.com/whyse-ab/ex-tales-forge/pull/42), [Design sketch: world agents](design-world-agents.md#round-2-results-2026-10-07)

## 2026-10-07: World agents round 2: prices from code, facts read from the narration

- **To try (not a final decision):** Elixir, not the GM, quotes prices. When the player's words mention something with a listed price, the server puts "Price: Bowl of stew, 5 copper" in the GM's per-turn data, or charges the coins itself and says "Purchase: …, paid". After the turn, off the critical path, one small LLM call (`fact_extract`, conv id `<session>:facts`) reads the finished narration for new facts and NPC promises; Elixir validates and stores them for the owning agent. The GM's own `new_facts` field is dropped.
- **Why:** in round 1 the GM still got prices wrong with the price in its facts, and it filled `new_facts` once in 20 turns. Prices are structured data, so code should state them (the call-type rule). Jev can't write text, so extraction is an LLM call.
- **Details:** [Design sketch: world agents](design-world-agents.md#round-2-results-2026-10-07), [ex-tales-forge PR #42](https://github.com/whyse-ab/ex-tales-forge/pull/42)

## 2026-10-07: NPC reactions on in playtest

- **Decision:** `NPC_REACTIONS=on` on tales-forge-playtest only (a Fly secret, like the other playtest switches); `WORLD_AGENTS` stays off there. Approved by Fredrik.
- **Why:** to see the Jev reaction (Brenna's mood and stance before each GM turn) in real playtests. The first Lotta check logged one `npc_reaction` row per turn (~$0.00004, 216–407 ms) and Brenna's replies varied, though she grew steadily warier over 5 turns.
- **Details:** [Fly secrets](fly-secrets.md), [Design sketch: world agents](design-world-agents.md#the-brenna-reaction)

## 2026-10-07: Merge the NPC reaction and world-agent prototype, off by default

- **Decision:** ex-tales-forge PR #40 is merged with both `NPC_REACTIONS` and `WORLD_AGENTS` off by default; production runs with both off. Approved by Fredrik ("Put it all in - I like it").
- **Why:** both flags cost nothing when off, the cached prefix is unchanged (prefix test), and having the code on main lets playtest and the next round build on it.
- **Details:** [ex-tales-forge PR #40](https://github.com/whyse-ab/ex-tales-forge/pull/40), [Design sketch: world agents](design-world-agents.md)

## 2026-10-07: To try: world agents hold facts

- **To try (not a final decision):** world agents (persons, locations, items, maybe animals) hold facts; the GM asks them for facts before narrating, and facts the GM invents are written back to the owning agent.
- **Why:** the prose-GM prototype drifted on lore (harpies instead of the orc nest) and on prices (a room for 2, 3 or 8 silver), and NPCs forgot promises. Facts kept by agents and sent per turn should keep the world consistent while the cached GM prefix stays small and stable.
- **Details:** [Design sketch: world agents](design-world-agents.md)

## 2026-10-07: Measure every call and turn step by call type

- **Decision:** every `ai_calls` row has a `call_type` (`function`, `jev`, `llm`) and adventure and game-system tags; the main Elixir steps of a turn are timed as zero-cost `function` rows. `/admin/costs` and playtest run reports show cost and p50/p90 latency per call type and purpose, the cache hit rate and the idle gap before each GM call, with persona cost kept apart.
- **Why:** so the call-type rule, caching and pricing can be checked with numbers instead of guesses.
- **Details:** [ex-tales-forge PR #39](https://github.com/whyse-ab/ex-tales-forge/pull/39), [Call types: recording call types and metrics](call-types.md#recording-call-types-and-metrics)

## 2026-10-07: Each bot call gets its own conversation id

- **Decision:** persona, scorer and intent calls send `x-grok-conv-id` `<session>:<purpose>`; only the scene and GM calls share the session id.
- **Why:** the persona bot's calls on the session id pushed the GM prompt out of xAI's cache between turns, so GM calls missed the cache.
- **Details:** [ex-tales-forge PR #37](https://github.com/whyse-ab/ex-tales-forge/pull/37)

## 2026-10-07: No length limits in the GM reply schema

- **Decision:** the strict GM/scene reply schema has no `maxLength` or `maxItems`; the caps on notes, summary and NPC memories are applied in code when the reply is parsed.
- **Why:** with `maxLength`/`maxItems` in the schema xAI does not reuse the prompt cache at all (every GM call reported 128 cached tokens); without them the same request reuses ~9k tokens.
- **Details:** [ex-tales-forge PR #36](https://github.com/whyse-ab/ex-tales-forge/pull/36)

## 2026-10-07: Elixir is the platform

- **Decision:** Tales Forge is built on Elixir: Phoenix LiveView, Ash, Oban and Jido. Decided by Fredrik, who funds the project.
- **Superseded in part:** the Ash part is superseded by [Ash removed for now; plain Ecto](#2026-10-07-ash-removed-for-now-plain-ecto-revisit-if-an-in-app-adventure-editor-needs-it) (2026-10-07).
- **Why:** the BEAM fits a soft real-time, always-on game with many concurrent sessions and agents.
- **Details:** [Why Elixir](why-elixir.md) (copy of the Google Doc [Why Elixir](https://docs.google.com/document/d/19w4sYfea-OamyPrnMk44hhbuVFDU9kKXirkqR_jjmtE))

## 2026-10-07: Decisions are recorded in this file

- **Decision:** decisions are recorded in this file, in this repo.
- **Why:** one place to see what was decided and why, with git history as the audit trail.

## 2026-10-07: Docs go straight to main

- **Decision:** documentation is committed straight to `main` in this repo, without pull requests; if something is wrong, undo it. Code still goes through pull requests, with Fredrik's OK before merge or deploy.
- **Why:** docs are cheap to fix and slow to review; code reaches players, so it keeps the review gate.
- **Details:** [Environments](environments.md) (how code reaches production)

## 2026-10-07: Call-type rule

- **Decision:** known structured input + structured output = Elixir function; unstructured input + structured output = Jev; prose output = LLM. Asking the LLM for structured output is a smell.
- **Why:** Elixir is exact, free and instant, Jev is fast and cheap, and the LLM is the slowest and most expensive; output length drives GM latency.
- **Details:** [Call types](call-types.md)

## 2026-10-07: GM pipeline direction

- **Decision:** Jev validates player input up front, so the GM prompt needs little hardening. Jev's intent plus Elixir's rules and rolls go to the GM as a typed struct with a short quote of the player's words. The GM uses a non-thinking model.
- **Why:** the GM only narrates prose, which makes turns faster and cheaper while keeping the player's tone.
- **Details:** [Call types: target turn pipeline](call-types.md#target-turn-pipeline)

## 2026-10-07: One Character type

- **Decision:** player characters and NPCs are technically identical (OCEAN personality, personality-filtered memory, Maslow level); only the controller differs (player or GM). NPCs run as their own Elixir agents with Jev gut reactions (System 1).
- **Why:** the GM can play an absent player's character with the same data and calls, and parties become possible later.
- **Details:** [Call types: character model](call-types.md#character-model)

## 2026-10-07: Measure cost and time per call type

- **Decision:** measure cost and time per call type (function, Jev, LLM) and per world/module, including cache hit rate.
- **Why:** so the call-type rule and pricing can be checked with numbers.
- **Details:** [Call types: recording call types and metrics](call-types.md#recording-call-types-and-metrics)

## 2026-10-07: Pricing direction (draft)

- **Decision:** no monthly subscription. Prepaid play time, billed only on GM response time; idle time is free. First character free. Working numbers: $1 per real hour, $3 starter, $5/$10/$20 top-ups.
- **Why:** players pay for what they use, and slow or casual play isn't punished.
- **Details:** [Pricing: a pool of play time](pricing-time-pool.md)

## 2026-10-07: All amounts in USD

- **Decision:** all amounts are in USD.
- **Why:** one currency for costs, prices and reports.

## 2026-10-07: Jev persona-affect scoring

- **Decision:** Jev scores persona affect 1-5 (frustrated to delighted) with confidence, per session and per turn, reading only player and GM spoken text, never hidden GM notes.
- **Why:** a cheap, typed signal of how a session felt, based only on what the player actually saw.
- **Details:** [Jev persona-affect scoring](jev-scoring.md)

## 2026-10-06: Character creation

- **Decision:** copy the working flow from tales-forge.ai, then move to a hybrid where each section (stats, background, social class, origin) offers own input or AI assist.
- **Why:** the old flow works today, and 4 of 5 personas preferred the per-section hybrid.
- **Details:** [Character creation port](character-creation-port.md), [persona preferences](character-creation-persona-prefs.md)

## 2026-10-06: The GM opens the scene

- **Decision:** the GM always opens the scene; players respond.
- **Why:** players start with something to react to instead of a blank prompt.

## 2026-10-06: One admin costs page

- **Decision:** all costs (Fly, Resend, domain, AI, GitHub) are shown on one admin costs page.
- **Why:** total running cost in one place.
- **Details:** [Infrastructure assets](infrastructure.md)

## 2026-10-06: Playtesting

- **Decision:** one end-to-end smoke test until all personas are ready, then intense bursts. Persona-bot time and tokens are measured separately from the game's own numbers.
- **Why:** don't spend on bot play before it's useful, and keep game cost figures clean.
- **Details:** [Design: playtest loop](design-playtest-loop.md), [Personas](personas.md)

## 2026-10-06: Branching and environments

- **Decision:** one always-deployable `main` with short-lived feature branches, per-PR preview apps, and a separate long-lived playtest Fly app. Bots need Fredrik's explicit OK before any deploy or merge of code.
- **Why:** production stays stable while bots and founders try changes safely.
- **Details:** [Environments](environments.md)

## 2026-10-06: Separate API keys per environment

- **Decision:** separate API keys per environment (xAI production vs playtest; TypeSafe per environment).
- **Why:** so costs split by environment, and one key can be revoked without breaking the other.
- **Details:** [Adding API keys and secrets to Fly](fly-secrets.md)

## 2026-10-06: Sign-in

- **Decision:** admin uses email magic links (no passwords), and logins last 30 days. Founders playtest via GitHub login, checked against the whyse-ab tales-forge team.
- **Why:** no passwords to store or leak, and founder access follows GitHub team membership.
- **Details:** [Setting up Resend](resend-setup.md), [Infrastructure assets](infrastructure.md)

## 2026-10-06: tales-forge.ai stays on Netlify for now

- **Decision:** tales-forge.ai stays on the existing Netlify site until the new Fly app is a working prototype.
- **Why:** players keep a working game until the replacement is ready.
- **Details:** [Infrastructure assets](infrastructure.md), [Environments](environments.md)

## 2026-10-05: North star

- **Decision:** the north star is the first paying customer the founders don't personally know.
- **Why:** everything is ordered by how much it brings that customer closer.
- **Details:** [Roadmap 2027](roadmap-2027.md)

## 2026-10-05: No assigning tasks

- **Decision:** nobody assigns tasks to people; founders self-assign. Plans are ordered lists, most important first.
- **Why:** founders choose their own work; the order says what matters most.
- **Details:** [Roadmap 2027](roadmap-2027.md)

## 2026-10-05: Fantasy first, own content first

- **Decision:** launch with fantasy only. The team builds the world and modules itself first; an author marketplace comes later.
- **Why:** prove the game in one genre with content we control before opening it up.
- **Details:** [Roadmap 2027](roadmap-2027.md)

## 2026-10-05: Acquisition

- **Decision:** RPG forums first, then word of mouth.
- **Why:** forums bring the first players; sharing brings the next ones.
- **Details:** [Roadmap 2027](roadmap-2027.md)

## Open questions

None right now. (Prose-only GM vs structured reply format: decided on 2026-10-08, see [the prose-only GM prototype is dropped](#2026-10-08-the-prose-only-gm-prototype-is-dropped-the-gm-has-one-structured-reply-mode).)

## 2026-10-10: Positive framing and ASD-STE100 language standard

- Decided by: Fredrik
- Speak about certainty, not doubt. In playtests, scores, UI and docs we say "confidence" or "certainty" (for example "confidence 0.8"), not "unsure", "uncertainty" or "unsureness".
- Avoid minimized negatives, such as "not unlikely" or "fewer failures", and double negatives. State the positive quantity directly.
- Code, code comments, moduledocs and docs use ASD-STE100 Simplified Technical English: short sentences, one instruction per sentence, active voice, and approved words with one meaning each.
- Existing names (for example `uncertainty` fields) are renamed to the confidence form as we touch them, with a cleanup PR for the rest.

## 2026-10-11: Security-bump lane

- Decided by: Fredrik
- A dependency bump that fixes a published advisory ships without a founder OK when all of these are true: only `mix.lock` (or version pins in `mix.exs`) changes, the version stays in the same major, and CI is green. The order is playtest, then a Gentry smoke check, then prod. Founders get a short note after it ships.
- A founder OK is still needed for a major version bump, for any code change needed by the fix, and for a fix that changes player-facing behaviour.
- High and critical advisories are fixed immediately, also outside working hours, under the same rules.
