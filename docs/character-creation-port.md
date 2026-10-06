---
title: "Plan: porting character creation from the old app"
updated: 2026-10-06
status: draft
---

# Plan: porting character creation from the old app

**Status:** draft, 2026-10-06. Research and a proposal only; no code has changed in either app.

Checked against the old app `fpahlen/tales-forge-new-31993d9d` on `development` (commit `20b791c`) and `whyse-ab/ex-tales-forge` on `main` (commit `0aa49e9`).

## Summary

The old app's character creation is a single-screen form with AI help. It does not involve the GM. The player picks a race, gender, class, home region and social status, and writes a short concept or has the AI write or expand one. One AI call then generates the full character: name, backstory, quote, stats, skills, starting gear priced against a wealth budget, appearance and personality. The server applies the racial bonuses afterwards. The player can edit the appearance and personality, add a pencil-sketch portrait if they want one, and save the character to their library. They start an adventure from there in a separate step. It takes one to three AI calls and a minute or two.

What makes it work is that a few choices and one click give you a character who belongs in the world. The name follows the world's naming lists, the backstory uses the home region and turns racial and social disadvantages into concrete details, and the gear fits the character's social class. The AI picks the stats, so the 75-point buy in the rules is never actually applied.

The new app has no creation step. Every session starts with Elara Voss. Most of the old flow ports easily: the prompts, the post-processing and the world data. The work is in five places: where the character is stored, getting the GM to see who the character is, loading creation data from the pack files, aligning the skill lists, and building the LiveView screen. Proposed order: let a session start with any character, make the GM see it, load creation data for one world, then build the screen and the AI step, then playtest support. Portraits and a character library come later.

## How the old flow works

### Steps

1. **Getting there.** New users with no characters are sent to the Welcome page (`src/pages/Welcome.tsx`), then to `/play/characters`. There the creation dialog opens by itself, with a six-step spotlight tutorial the first time (`src/pages/play/CharactersPage.tsx`, `src/components/tutorial/CharacterCreationTutorial.tsx`). Returning players open it with a floating "Create Character" button. You need an active world (module) first.
2. **The form** (`src/components/CharacterGenerator.tsx`, inside `src/components/generators/CharacterGeneratorDialog.tsx`). It sits on the left, with the result on the right. Each dropdown shows a short description of the selected option.
   - **Race** (labelled from the world, e.g. "Heritage" in Penny Dreadful). Defaults to the first race in the list, Human. The list is filtered by a `playable` flag; for the go-to-market launch only Human, Elf, Dwarf and Half-Elf were playable (`docs/development/completed/feature-go-to-market.md`).
   - **Gender:** Random (default), male or female.
   - **Class:** defaults to the first archetype, Warrior. The launch allowed only Warrior, Thief and Ranger.
   - **Home region:** a barony. Only shown if the world has regions. Defaults to Random, which the server resolves to a random barony.
   - **Social status:** taken from the world's `currency.starting_wealth` keys, from nobility down to underclass. Defaults to commoner.
   - **Aurilian heritage** checkbox (Latin names). Only shown if the world has that naming pool.
   - **Character description,** free text up to 16,384 characters, with a sparkle button. On an empty field it writes a random two-sentence concept in the second person. If the player has already typed something, it expands that text and keeps every name, relationship and secret they wrote. This "player starts, AI expands" pattern is used across the app's generators (`src/components/ui/ai-textarea.tsx`).
3. **Generate Character.** This needs a description. One call returns the whole character, shown on the right: name, race, background line, quote, backstory, six stats, five to eight skills with levels, appearance, personality and equipment. A toast and an amber "not saved yet" warning tell the player to save. The dialog ignores outside clicks and Escape, so the character isn't lost by accident (`docs/development/completed/feature-beta-character-creation.md`).
4. **Edit.** Only appearance and personality can be edited. Name, stats, skills and gear can't. To change them the player generates again, which replaces everything. The player can't type a name; the AI always picks one (`name: undefined` is always sent).
5. **Portrait** (optional). "Generate Portrait" either reuses a stored portrait with a similar prompt or makes a new one in the world's image style. Merovingia uses black-and-white pencil sketches.
6. **Save Character to Library.** This calls the `insert_character` RPC and attaches the portrait. The character is tied to the world it was made in.
7. **Starting play** is a separate step (`src/components/library/CharacterSessionStarter.tsx`). From the character card, "Begin Adventure" asks the player to pick a world, then reuses or creates the player's campaign for it. It finds the start location and the NPCs there, works out starting coins (the wealth budget minus the gear's value), seeds the inventory from the gear and creates the session. The chat page then has the GM write the opening scene.

There is no single "randomise everything" button. The random options are gender, home region and the sparkle-written concept, and the defaults (Human, Warrior, commoner) mean a player can get a full character by pressing the sparkle button and then Generate.

**Time:** not measured. My estimate is one to three minutes. The concept call is short (600 output tokens at most). The character call allows up to 3,000 output tokens, which should take roughly 5–15 s on the fast Grok model. A new portrait takes about 10–20 s, or no time at all when a similar one is reused.

### Rules and world data

The flow is generic: everything world-specific comes from the module's `game_system` record, stored in Supabase `module_content` and read through `get_effective_module_content`, so child modules inherit it (`supabase/functions/_shared/gameSystem.ts`). The files in the repo are `modules/merovingia/game-system.json` and `modules/penny-dreadful/game-system.json`. The Merovingia file is identical to [worlds/merovingia/game-system.json](../worlds/merovingia/game-system.json) in this repo.

- **Races** (`variants`): stat modifiers and a skill bonus, which is either a pool of points (Human +5, Half-Elf +3) or set skills (Elf +3 Ranged Combat, +2 Survival). Each race also has traits and disadvantages.
- **Archetypes:** the class list, with descriptions and suggested skills.
- **Skills:** 38 in Merovingia, each in one of five domains.
- **Starting wealth** by social status, used for the status list.
- **Naming:** name pools and rules. French names are weighted more heavily the higher the status, English names are used for commoners, Latin names for Aurilian heritage, and there are race name components and regional twists. These are turned into prompt guidance by `supabase/functions/_shared/namingRules.ts`.
- **Home region text:** the barony markdown, cut down to a short context by `supabase/functions/_shared/worldContext.ts`.
- **Tone, genre, GM title and portrait style:** `setting_tone`, `genre`, `gm_title` and `image_style`.

Some of it is hardcoded and Merovingia-specific, even though the flow looks generic:

- **The wealth budget** (nobility 26,000 copper down to underclass 50) is hardcoded twice, in `supabase/functions/_shared/coinUtils.ts` and `src/lib/inventoryCalcs.ts`. It matches Merovingia's table, so Penny Dreadful's own `starting_wealth` is ignored.
- **Minimum gear prices** are a keyword list in `supabase/functions/_shared/equipmentPricing.ts`.
- **Social status traits** are read from `game_system.social_status_traits`, but neither world file has any. So in practice the narrative seeds are only the racial traits and disadvantages.
- **The written rules** (`docs/game-rules/fantasy_rpg_game_mechanics_summary.md`) have the 75-point stat buy and 20–30 skill points capped at 5, the same rules the new app's Tin Valley and Crossroads packs carry. The generator doesn't use them: the AI picks base stats aiming for a total of 74–79, and gives five to eight skills at levels 1–15.

### AI calls

All AI calls go through `callAIWithDefaults` in `supabase/functions/_shared/aiProvider.ts`. The provider is a database setting: Grok by default (`grok-4-1-fast-non-reasoning` for text, `grok-imagine-image` for images), with Gemini 2.5 Flash as the alternative. Every system prompt starts with a security preamble that treats player text as in-game content only. Calls are rate-limited and logged to a content gateway.

| Call | Edge function | Task, settings | Prompt (in `supabase/functions/_shared/prompts.ts` unless noted) | Output |
|---|---|---|---|---|
| Concept (sparkle), optional, repeatable | `generate-character-description` | `character-description`, temp 0.8, 600 tokens | `characterDescription` system prompt (two sentences, second person, background plus a hook) and `buildCharacterDescriptionPrompt` (generate, or expand while keeping the player's names) | Plain text |
| Character, required, repeatable | `generate-character` | `character-generation`, temp 0.7, 3,000 tokens, JSON schema `_shared/schemas/characterResponse.ts` | `characterGenerator` system prompt (stats ignore requests like "max stats", typical total 74–79, at most one 18) and `buildCharacterPrompt` (race, class, concept, home region, gender, naming guidance, narrative seeds to weave in, wealth budget with price bands) | JSON character |
| Portrait, optional | `generate-portrait` | `portrait-generation` | `buildCharacterPortraitPrompt` in `_shared/imageStyle.ts`, with the world's image style and the user's drawing style; checks for a similar existing portrait first | Image, stored in the `portraits` bucket |

That is one to three calls per character. Every sparkle click or extra Generate adds one more.

After the character call, the server fixes gear prices that are too low and adds the racial stat modifiers, clamped to 3–18. It adds set-skill bonuses (capped at 15) and records the race, class, social status and narrative seeds (as `traits`, hidden from the player). It also sets wounds: maximum = 3 + (CON − 10) / 2.

### Data shape, storage and hand-off

- **Generated character** (client type in `CharacterGenerator.tsx`): `name`, `gender`, `race`, `class`, `background`, `backstory`, `quote`, `personality`, `appearance`, the six stats in full words (`strength` … `charisma`), `skills: [{name, level, lp}]`, `equipment: [{name, copperValue, category}]` (category is equipped, consumable or pack), `traits: [{name, description, type}]`, `socialStatus` and `max_wounds`.
- **Stored** in the Supabase `characters` table through `insert_character` (`supabase/migrations/20260528195900_remote_schema.sql`). The columns include the fields above plus `module_id` (required), `user_id`, `social_status`, `image_url`, `armor`, `level`, `current_wounds`, `max_wounds`, `is_shaken` and `personal_hook`. The portrait is linked through the `portraits` table.
- **Hand-off:** `insert_game_session` gets `character_id`. Coins and inventory are worked out when the session starts and stored in `session_state`. Each turn, `langgraph-game-session` reads the character row. The GM prompt's "CURRENT CHARACTER" block (`buildDMSystemPrompt` in `prompts.ts`) has the name, race, class, social status, stats, wounds, armor, trait names and skill levels. A separate section tells the GM to use the backstory for complications.

### What the founders probably like

- **Fast, with a good result:** a handful of choices and one click give a complete character with a name, a voice (the quote) and a past.
- **"Player starts, AI expands":** the sparkle button fills an empty field, or expands what the player wrote and keeps their names and secrets.
- **Grounded in the world:** the backstory uses the home region's culture and tensions, the name fits the race, status and region, and the gear fits the social class.
- **Weaknesses turned into story:** racial disadvantages become concrete details, such as a named creditor or a village that turned the character away, and the GM is told to bring them back in play.
- **Hard to cheat:** the stats ignore requests like "max stats" in the description, and gear prices are checked on the server.
- **A pencil-sketch portrait** in the world's style.
- **Driven by world data:** the same screen works for Penny Dreadful (Heritage, Narrator, Victorian names) without code changes.
- **Gentle onboarding:** the spotlight tutorial, descriptions under each choice, and protection against losing an unsaved character.

### Rough edges

- **The written rules aren't applied.** The AI picks the stats and skills, so the 75-point buy and the skill cap of 5 aren't enforced. Skills can start at up to 15.
- **Some racial bonuses are lost.** The Human "+1 to any two stats" exists only as a note, so it's skipped. The skill pools (Human +5, Half-Elf +3) come back as `bonusSkillPoints`, which the screen never shows and the save never stores.
- **Little editing.** The player can't choose a name or change stats, skills or gear. Generating again replaces everything.
- **Values that are lost on save.** The prompt asks for `armor`, but it isn't in the JSON schema or saved. The server works out `max_wounds`, but `insert_character` has no field for it, so the database default of 3 is used. The `personal_hook` column is never filled.
- **The portrait prompt gets the gear wrong.** Gear items are now objects, but `generate-portrait` joins them as strings, which probably puts "[object Object]" in the prompt. The `gender` it is sent is ignored.
- **The home region may be missing from the concept.** Baronies are stored as content type `district`. `generate-character` looks them up as `district`, but `generate-character-description` looks for `barony`, so the sparkle concept probably never gets the home region. It is also sent the social status and Aurilian flag but doesn't use them.
- **The backstory may never reach the GM.** On the default Grok path the GM's character block has no backstory, appearance or personality. They only go into the Gemini context cache (`_shared/caching/sessionCacheManager.ts`), and even that leaves out the backstory. So the hooks woven into the backstory may never reach the GM, even though its prompt calls the backstory its main source of story hooks.
- **Merovingia's wealth table is hardcoded** (see above).
- **Creation and starting play are two separate dialogs,** and the world has to be picked twice. The premortem notes that most users made one character and played once (`docs/development/premortem-may-2026.md`).
- **No draft:** closing the dialog without saving loses the character. A draft was deferred after the beta.

**Secrets:** no secrets are hardcoded in the character creation code. Elsewhere in the old repo, the production Supabase publishable (anon) key is hardcoded as a fallback in `supabase/functions/langgraph-game-session/comparison.test.ts` and in the setup guides under `docs/development/local_development/`. Publishable keys are meant to be public, but the value is written out there.

## The new app today

- **Elara Voss** is defined in `TalesForge.Game.World.default_world_state/0` (`lib/ex_tales_forge/game/world.ex`). Crossroads uses that state directly. Tin Valley gets her through `TalesForge.Game.Pack.materialize/1` (`lib/ex_tales_forge/game/pack.ex`), which copies `World.default_world_state()["character"]` and only changes `location_id`.
- **The character has no table of its own.** It is the `"character"` map inside `game_sessions.world_state` (`lib/ex_tales_forge/schemas/game_session.ex`: `name`, `status`, `world_state`, `world_clock`). The map holds `id`, `name`, `race`, `location_id`, `stats` (`"STR"` … `"CHA"`), `skills` (snake_case name to level), `learning_points`, `learning_failures`, `wounds`, `wound_max`, `vitality`, `coins` (`gold`, `silver`, `copper`) and `inventory` (`[%{"id", "name", "quantity"}]`).
- **Starting a session:** `HomeLive` has a button for Tin Valley and one for Crossroads, and each calls `GameSessions.create_session/1`. That builds the world, seeds NPCs and fronts, starts the session agent and enqueues the opening scene straight away (`ensure_scene/1` and the `ProcessScene` job). Players can't act until the scene exists (`submit_message/3` returns `{:error, :needs_scene}`), so the GM always opens.
- **What the GM sees of the character:** `Context.character_summary/1` (`lib/ex_tales_forge/game/context.ex`), which has only the name, vitality, wounds, coins, inventory and location. Race, stats, skills and anything about who the character is never reach the scene or GM prompts. Stats and skills are only used on the server, by `TalesForge.Game.Mechanics`.
- **Skills:** `Mechanics` has a hardcoded list of 17 skills, each tied to a stat (`@skill_stat`). The intent step offers only these. Merovingia has 38 skills, with different spelling ("Melee Combat" against `melee_combat`).
- **Rules:** the Tin Valley and Crossroads packs (`priv/adventures/*/rules/`) are prose markdown fed to the GM. They have the point buy, races and the wealth budget table, but no structured data the code could build a form from.
- **AI:** `TalesForge.LLM` does JSON-schema calls on `TIER1_MODEL` and `TIER2_MODEL`. Each call is recorded in `ai_calls` (`game_session_id` can be empty) and checked against the spending caps. Image generation is a stub (`lib/ex_tales_forge/images.ex`).

## What maps easily and what needs rework

**Maps easily**

- **The prompts.** The concept and character prompts, the security wording and the JSON schema carry over almost word for word into an `LLM` call with a schema.
- **The post-processing.** The racial modifiers, clamping to 3–18, price floors and the wealth budget are small pure functions. The wound formula is already the same: `Mechanics.wound_max/1` is 3 + (CON − 10) / 2.
- **The data.** Merovingia's `game-system.json` is already in this repo, and Tin Valley's `economy.md` has the same wealth budget table.
- **Naming guidance** is a pure function of the naming data.
- **The opening scene.** The GM already opens every session. A character passed into `create_session` is in place before the scene job runs.

**Needs rework**

- **The character shape:** the stats need renaming, the skills become a snake_case map, the gear becomes inventory items plus coins (budget minus gear value), and the new fields (background, backstory, personality, appearance, quote, gender, archetype, social status, hidden seeds) need a home in the map.
- **Data loading:** the old app read the game system from Supabase with inheritance. The new app reads pack files under `priv/adventures/`, so it needs a loader that validates the data and fails fast, like `Pack`.
- **Tin Valley has no structured creation data.** Its races and point buy exist only as prose, and there's no archetype or class list. Its `races.md` also differs from Merovingia's JSON in places: Elf gets "+1 INT or WIS" against a fixed +1 INT, and Half-Elf gets +1 DEX +1 CHA against +1 CHA +1 INT.
- **The skill lists** have to agree, or a created character's skills won't resolve in play.
- **The screen:** a React dialog with state in the browser becomes a LiveView that keeps the draft on the server. The 5–15 s character call should run without blocking the screen, with progress sent over PubSub as scenes already are.
- **The GM context** has to include who the character is, or the creation step makes no difference to the story.
- **Spending caps:** creation happens before a session exists, so only the day cap applies, unless creation creates the session first.
- **Portraits** need a real image pipeline and storage (Tigris).

## Proposed port

In order, most important first. Sizes are rough: S is about a day, M is two to four days, L is one to two weeks.

1. **Let a session start with any character (S).** `GameSessions.create_session/1` accepts a `character` map. `Pack.materialize/2` uses it instead of Elara, adds `location_id` and works out `wound_max` and `vitality`. Elara stays the default, so existing paths and tests keep working.
2. **Make the GM see who the character is (S).** Add race, archetype, social status, background, backstory, personality, appearance, stats and skills to `Context.character_summary/1`, or put them in a separate character section of the GM prompt. In the scene prompt, ask the GM to give the character a reason to be in the opening scene, based on their background, as the old app did for random scenes. Keep the hidden seeds GM-only.
3. **Load structured creation data for one world (M).** Add a loader such as `TalesForge.Game.CreationRules` for a structured file in each pack: races, archetypes, skills with linked stats, social classes with wealth budgets, naming lists, point-buy limits and the starting skill cap. Write that file for Tin Valley from its `races.md`, `core_mechanics.md` and `economy.md`; Crossroads shares the same rules. Merovingia's `game-system.json` already has nearly this shape.
4. **Align skills with world data (S–M).** Take `Mechanics` skills and their linked stats from the loaded data, with the current 17 as the default, so the intent step and checks accept every skill a created character can have.
5. **The creation screen (M).** A LiveView such as `/new/:adventure`, opened from the home page buttons. It has the choices with descriptions, a free-text concept with a "write it for me" or "expand mine" button, then Generate, then a review of the sheet with editable name, appearance and personality, then "Begin adventure". That calls `create_session` with the character and goes to `/play/:id`, where the GM opens. Keep the creation logic in a separate context module such as `TalesForge.CharacterCreation`, not inside the LiveView, so the playtest runner can drive it too.
6. **AI generation and server checks (M).** Two `LLM` purposes, `character_concept` and `character_sheet`, ported from the old prompts and schema and recorded in `ai_calls`. Afterwards the server applies racial modifiers and clamping and checks the result against the world's limits (stat total, skill cap, known races, archetypes and skills). It applies the price floors, turns gear into inventory plus coins, and adds the naming guidance. Fix the old rough edges on the way: keep skill pools and the "+1 to any two" choice, and save armor and wounds.
7. **Playtest support (M).** See the next section.
8. **Apply the point buy for real (M, depends on the founders' answer).** Either the AI proposes a build inside the 75-point buy and the player can adjust it, or the server rescales whatever the AI returns. Both use the same validator from step 6.
9. **Merovingia as a playable world (L).** Load `game-system.json` for creation and add an adventure pack with a start location and NPCs. Without the pack there's nowhere to play.
10. **Portraits (M–L).** Image generation and Tigris storage in `TalesForge.Images`, reusing the old portrait prompt and world style. It runs in the background so it never delays the opening scene.
11. **A character record that outlives a session (M).** A `characters` table for a library, the character museum and making the next character after a death. This ties to [D-010](../decisions/d-010-death-revival-fantasy.md) and the `characters` table in [Game data vs sessions](design-game-data-vs-sessions.md).

Steps 1 and 2 are worth doing first on their own: they make any character, even a hand-written one, actually show up in play.

## Persona bots in playtest

The [playtest loop](design-playtest-loop.md) has a section, *Scenario: character creation* (open PR #10 in this repo), that lists what each persona does and what gets scored. This is how the port could support it:

- **Same paths as a player.** The runner (`TalesForge.Playtest.Runner`) calls the `TalesForge.CharacterCreation` functions behind the screen, then `create_session` with the result. It then waits for the GM's opening, as today. A creation-only test stops there; a full test goes on to play.
- **What the bot sees.** `PlayerView` gets a creation view: each choice as a question with options and descriptions, the concept field, and the generated sheet. That matches the persona reply the runner already uses for GM questions (`action` plus `option_id`). The bot picks an option or writes text, such as Paul's prose concept, Lotta's own name and details, or Ronny's attempts to get 20 STR.
- **Automatic checks** reuse the step 6 validator: race, archetype and skills exist in the world data, stats and skill points are within limits, coins and gear match the social class, and the name fits the naming lists.
- **What gets recorded:** time and steps from start to finished character, the number of regenerations, and creation `ai_calls` under their own purpose so creation cost can be told apart from play. The judge reads what the bot saw and the sheet it ended up with.

## Open questions for the founders

1. Should creation be a form with AI help like the old app, a conversation with the GM, or a form first with the GM filling in the story?
2. Should the AI keep picking the stats as before, or should the 75-point buy in the rules really apply? If so, does the player adjust the numbers, or does the AI build inside the limits?
3. Which world first: Tin Valley, which the new app can load but which has no structured race or class data yet, or Merovingia, which has the richest data but no adventure in the new app?
4. Should Elara, or a few ready-made characters, stay as a quick start for players who want to play straight away?
5. Are portraits part of the first version, given the extra cost and wait?
6. Which parts of the generated character should the player be able to change: name, stats, skills, gear?
7. Is a character tied to one session, or kept so it can be played again? What happens after a death: the same creation again, or a shorter one?
8. Do we keep the five social classes, with their effect on money, gear and names?
9. Should the hidden weaknesses woven into the backstory stay hidden from the player, as in the old app?
10. Do all races and classes open at once, or a smaller set first, like the old launch's four races and three non-magic classes?
11. What is a good target time for making a character?
12. Should creation count against the per-session spending cap?
