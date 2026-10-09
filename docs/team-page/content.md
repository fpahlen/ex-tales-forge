---
title: "Team page (/team): content brief"
updated: 2026-10-09
status: brief for Bobby
---

# Team page (/team): content brief

**What this is:** the copy, chart specs and image ideas for a founders' presentation page at `/team` in the production app (`tales-forge`), behind the existing GitHub team sign-in. Bobby builds it as a LiveView page; this file and [`data.json`](data.json) are the content and numbers only, no app code.

- **Audience:** the Tales Forge founders (the `whyse-ab/tales-forge` GitHub team). Most aren't deep in the setup. Fredrik presents from it.
- **Tone:** plain, warm, a little proud. Any technical term gets a one-line explanation the first time it shows up.
- **Money:** USD everywhere.
- **Never on the page:** secret values, keys or tokens. Saying *where* a secret is kept is fine; showing the value is not.
- **Numbers:** every number comes from `data.json` (given here as `key.path`). Where we don't have a number, the page says "not measured yet" rather than guessing.
- **As of:** 2026-10-09 (Stockholm time). Show "Numbers as of 9 Oct 2026" in the footer, read from `_about.as_of`.

Suggested layout: one long page with a sticky section nav (Team · How we work · Infrastructure · Playtests · Pace and cost). It should work on a phone at 320 px wide, since Gentry checks exactly that.

---

## 0. Hero

**Headline:** How Tales Forge gets built

**Subhead:** One founder, three bots, and a lot of small, careful steps. Here's who does what, how a change gets from an idea to the game, and what we've learned from letting bots play it.

**Three stat tiles** (big number with a small label):
- `pace.prs_merged` pull requests merged *(a pull request, or PR, is one proposed change to the code that someone reviews before it goes in)*
- `decisions.total` decisions written down
- `pace.tests.total` automated tests, all passing

---

## 1. The team

**Intro copy:**
> Tales Forge has one human and three bots on the build team. The bots do a lot of the work, but nothing reaches the game without a human yes.

**Cards** (one per member, from `team.members`; avatar, name, role, 3–4 bullets, a schedule badge where there is one):

**Fredrik**, founder and funder *(human)*
- Decides what we build and why.
- Approves every code merge and every deploy. No exceptions.
- Presents this page.

**Case**, point of contact and architect *(bot)*
- The one Fredrik talks to. Turns ideas into plans and hands the work to Bobby.
- Reviews the architecture on every merge, in the spirit of *The Pragmatic Programmer* (a classic book on keeping code simple: don't repeat yourself, fix broken windows early, keep decisions reversible).
- Posts an hourly status, cleans up old branches every day, and does the research and analyses behind our decisions.
- Badge: "Hourly status · daily cleanup"

**Bobby**, Elixir developer and devops *(bot)*
- Writes all the code, always as pull requests.
- Runs the persona playtests and the evals *(an eval is a fixed test set we score the AI against, so we can tell if a change made it better or worse)*.
- Deploys to Fly *(our hosting)* only with Fredrik's OK.
- Checks the Fly logs every hour.
- Badge: "Hourly log check"

**Gentry**, picky adversarial QA *(bot, playtest only)*
- Plays the game like a troublemaker: prompt injections *(text that tries to trick the AI into ignoring its rules)*, fake GM notes and false claims ("the GM already said I have the sword").
- Also checks broken links, speed, phone layout and accessibility.
- Every attack Gentry finds goes into the intent eval set, so the game gets harder to fool over time.
- Never touches production.
- Badge: "Weekdays 07:13 · after every playtest deploy"

**Small strip under the cards** (from `team.other_bots_note`):
> Fredrik also has other bots for company admin, like bookkeeping, invoices and mail. They don't work on the game.

### How a change flows

**Copy:**
> Every change takes the same path. It looks like a lot of steps, but most take minutes, and the median PR went from opened to merged in about 15 minutes in October.

Steps (from `change_flow.steps`):
1. **Idea.** From Fredrik or any founder.
2. **Case** plans it and writes the brief.
3. **Bobby** builds it as a pull request.
4. **CI** runs. *(CI, continuous integration: robots that run every test and check on every PR. If anything fails, the PR can't merge.)*
5. **Fredrik's OK.**
6. **Merge** into `main`, the version that runs the game.
7. **Case's architecture review** of what just landed.
8. **Deploy to playtest**, our separate copy of the game for testing.
9. **Gentry** attacks it.
10. **Playtest batch**: the five persona bots play it, and Jev scores how each would have felt.
11. **Production**, where players are.

Footnote from `pace.median_hours_open_to_merge_oct` (0.24 h ≈ 15 min).

> **Note for Fredrik (not page copy):** `docs/environments.md` (2026-10-08) still says a merge to `main` deploys to production automatically and then to playtest. The flow above is the one in your brief. Pick one before presenting, and update the other.

**Animation spec: "flow"**
- **Type:** a horizontal step animation (vertical on phones). A small glowing token (a d20 die fits the game) travels through the 11 steps. Each step lights up with its owner's avatar.
- **Data:** `change_flow.steps[].label` and `.who`.
- **Behaviour:** it plays once when scrolled into view, with a "replay" button, and respects `prefers-reduced-motion` (show the static diagram then). At the "Fredrik's OK" step the token pauses with a small ✓ stamp, because that's the point to make.

---

## 2. How we work

**Intro copy:**
> A few simple rules keep three bots and one human pulling in the same direction.

**Rule cards:**

1. **Decisions are written down.** Every decision goes into one log, `docs/decisions.md` in `tales-forge-docs`, with the date, the decision, why, and a link to the details. Changing a decision means adding a new entry, never editing history.
   - Stat: **`decisions.total` decisions in five days** (5–9 Oct).
   - Plus a decision queue of `decisions.queue.total` bigger questions (`decisions.queue.open` still open), and a future-ideas list (`decisions.future_ideas.count` ideas so far: *speculative intent while typing* and *memory consolidation and attitude drift*).
2. **Docs go straight to main; code goes through PRs.** Writing things down should be fast, so docs need no review step. Code always gets a PR, CI and Fredrik's OK.
3. **The call-type rule.** Each piece of work in a turn uses the cheapest tool that can do it:

   | What goes in | What comes out | We use | Why |
   |---|---|---|---|
   | Known structure | Known structure | **Elixir code** | exact, free, instant |
   | Free text or a messy situation | Known structure | **Jev** | fast and cheap (about $0.0001 a call) |
   | Anything | Prose a person reads | **An LLM (Grok)** | slowest and most expensive, so it goes last |

   One-liners: *Elixir is the programming language the game is written in. Jev is TypeSafe's model that reads text and answers with typed data (a category plus a confidence), not prose. An LLM is a large language model, the kind of AI that writes text.*
   Data: `call_types.rows`.
4. **Code that explains itself.** "Humans may need to understand the code one day." Every module says what it's for, every public function has docs and a type spec, and the tools check it all on every PR:
   - doctests *(examples in the docs that also run as tests)*;
   - Dialyzer *(a type checker)*: `code_standards.dialyzer_warnings` warnings;
   - Credo *(a style checker)* and the formatter;
   - tests for every change, with coverage up from 73.3% to `code_standards.coverage_pct`% in two days.

**Chart spec: "decisions per day"**
- **Type:** a small vertical bar chart, one bar per day.
- **Shows:** decisions logged per day, 5–9 Oct (9 Oct is partial).
- **Data:** `decisions.by_date[]` (`date`, `count`).
- **Caption:** "Oct 7 was the big one: 40 decisions in a day, mostly small, all written down."

---

## 3. Infrastructure

**Intro copy:**
> The game is a small, sturdy web app. Here is what it runs on, in plain words.

**Stack list** (icon and one line each; from `infrastructure.stack`):
- **Elixir and Phoenix LiveView.** The language and web framework. LiveView keeps the page live over one connection, so the story updates without page reloads.
- **Ecto and Postgres.** The database layer and the database: sessions, characters, turns and costs.
- **Oban.** Background jobs, such as running a turn or a playtest, so nothing blocks the page.
- **TypeSafe Jev.** Reads what the player meant (intent), flags tricks (safety) and scores playtests.
- **Grok (xAI).** The Game Master model. It writes the story, and only the story.
- **Fly.io, Stockholm.** Two apps: `tales-forge` (production, release `infrastructure.apps[0].release`) and `tales-forge-playtest` (playtest, `infrastructure.apps[1].release`).

**Safety and access cards:**
- **One way in:** "Sign in with GitHub", only for members of the founders' team, on every page of both apps.
- **Separate keys:** production and playtest have their own AI keys, so bot testing never mixes with real play in the bills. The keys live in Fly's secret store; nobody pastes them anywhere.
- **Costs pages:** `/admin/costs` shows AI spend per day and month. Production shows everything, with playtest's costs read live from the playtest app.

**Hosting cost tile:** "About $`infrastructure.hosting_total_usd_per_month`/month for hosting and the domain, before AI usage." Expand to show `infrastructure.hosting_usd_per_month[]`.

**Diagram spec: "how a turn works" (architecture)**
- **Type:** a left-to-right flow diagram (top-to-bottom on phones), drawn as SVG.
- **Nodes** (`infrastructure.architecture_nodes`): Player → LiveView → **Jev: intent + safety** → **Elixir: rules and state** (dice, prices, world) → **GM LLM (Grok)** → prose back to the player.
- **Colour by call type**, using the same three colours as the call-type table: Elixir nodes one colour, Jev another, LLM a third. The legend repeats the rule.
- **Annotations:** under Jev, "~255 ms, $0.00013 a turn" (from `intent_shadow`). Under Elixir, "decides what happened, and saves it first". Under the GM, "writes the story, never the facts".
- **Caption:** "The rules decide what happens. The AI only tells the story."
- **Honesty note** (small print): today Jev intent runs in *shadow* on playtest (it reads every turn, but the old path still decides) and is off in production.

---

## 4. Playtests

**Intro copy:**
> We can't hire a hundred players yet, so we built five pretend ones. Each persona bot plays the game the way a real kind of player would, and Jev reads every session and asks: how would *this* player have felt?

**Persona cards** (from `personas.items`; avatar, name, play style, one line, and their test character's name in small text):
- **Hawk**, hard mode: wants a real fight and real risk; hard but fair, with danger foreshadowed.
- **Paul**, role playing: theatrical and in character; story first, and hates visible mechanics.
- **Lotta**, identification: wants to be someone different, and wants the world to react to who she is.
- **Lars**, adventurer: action, clear quests and visible progress; wants to change the world.
- **Ronny**, the anti-persona: bends rules for loot and levels. We *don't* build for Ronny; a high Ronny score means the game held firm.

**How scoring works** (short copy):
> Jev gives each turn a score from 1 (frustrated) to 5 (delighted) for that persona, plus how sure it is. The headline is a **confidence-weighted average**: every turn counts, and the turns Jev is unsure about count less. We show it as "4.3/5 · unsure 46%", so you can see both the score and how much to trust it.

Data: `jev_headline`.

**Chart spec: "persona scores over time"**
- **Type:** a grouped bar chart (or dot plot): x = series in time order, one bar or dot per persona, y = 1–5.
- **Shows:** the confidence-weighted turn score per persona over the four comparable series.
- **Data:** `playtest_series.series[]` → `label`, `weighted.{paul,lotta,lars,hawk,ronny}`. Tooltip: `unsure_pct`, `completed_runs`.
- **Styling:** draw Ronny dashed or greyed, with the label "anti-persona". Draw a light band at ±0.3 labelled "noise at this sample size".
- **Caption:** "Small batches, so small moves are noise. The clear win is Hawk: once the game gave him a real antagonist, his scores came up."

**"What changed" highlight list** (from `playtest_series.highlights`):
- Hawk without a fight: 2.54 → **3.14** after we gave him an antagonist gang (the Tinjacks).
- The GM parroting the player's words: 22% → **5%** of turns.
- Runs that left the starting inn: 0 → **12 of 23**.
- Characters growing skills: 0 → **13 levels** in 23 runs.

### Jev intent: the shadow test

**Copy:**
> We're replacing a keyword guesser with Jev for working out what the player meant. Before switching, we ran Jev in *shadow*: it read every turn on playtest but didn't change anything, so we could compare.

**Stat row** (from `intent_shadow`):
- **125** turns read
- **255 ms** median, **340 ms** p95 *(95% of reads were faster than this)*
- **all 125** inside the 1.5 s limit
- **$0.016** total, about **$0.00013 a turn**
- **33%** of turns read materially differently from today. In the examples we checked, Jev was the one that got it right.

**Example callout** (from the analysis doc):
> Player: *"Good folk, the Light teaches that even the fiercest storm may be calmed with patient words…"*
> Today's guesser: **combat**. Jev: **talk to the innkeeper**. ✔ Jev

**Chart spec: "intent latency"**
- **Type:** a horizontal bullet chart: p50 and p95 markers against a 1,500 ms bar, with max as a faint tick.
- **Data:** `intent_shadow.p50_ms`, `p95_ms`, `max_ms`, `timeout_ms`.

**Chart spec: "agreement with today's path"**
- **Type:** horizontal bars, 0–100%.
- **Data:** `intent_shadow.agreement_with_today_pct` (action, class, target, skill, later).
- **Caption:** "Low agreement mostly means the old guesser was wrong, not Jev."

### The eval set

**Copy:**
> To trust Jev, we built an exam for it: 350 real and hand-written player lines with the right answers, split so we tune on one part and keep the other part unseen until the end.

**Stats** (from `intent_eval_set`):
- **350** items: **247** tune, **103** held out *(never looked at while tuning, so the final score is honest)*.
- **217** from real playtests, **133** written by hand, including **60** attacks (injections, jailbreaks, nefarious requests).
- **On the tune split after tuning:** action right **95.1%**, attacks caught **42/42**, false alarms **0 of 205**.
- **Held-out result:** not run yet. It runs once, on frozen settings, before production.

**Chart spec: "what's in the exam"**
- **Type:** a stacked horizontal bar or treemap of categories, coloured real vs attack vs tricky.
- **Data:** `intent_eval_set.categories`.

### Gentry's findings so far

**Copy:**
> Gentry started on playtest this week. The first catch was not an exploit but something every phone player would have hit.

From `gentry_findings`:
- The **Act** button was cut off on small phones (320 px wide). Fixed in PR #89.
- The admin menu scrolled sideways on phones. Now it wraps.
- The theme buttons had no labels for screen readers. Now they do.
- Also noted: the home page lists 150 sessions, there's no sign-out on the play pages, and the story panel is very short on phones.

**Gap to show honestly:** "Hostile-play results (injections, fake GM notes, false claims) will appear here once Gentry has logged them." (`gentry_findings.hostile_play_results` is null.)

---

## 5. Pace and cost

**Intro copy:**
> Bots are fast. These numbers show how fast, and what it cost.

**Stat tiles:**
- **`pace.prs_total`** PRs (`pace.prs_merged` merged, `pace.prs_open` open)
- **`pace.commits_main_ex_tales_forge`** commits on the game's main branch
- **`pace.tests.tests` tests + `pace.tests.doctests` doctests**, 0 failing, `pace.tests.coverage_pct`% coverage
- **`decisions.total`** decisions logged

**Chart spec: "PRs per day"**
- **Type:** a paired bar chart, created vs merged per day (Stockholm dates).
- **Data:** `pace.prs_by_day[]` (`date`, `created`, `merged`).
- **Note:** July is the first scaffold phase and the real push starts 5 Oct, so use a broken x-axis or show Oct only with a "+14 PRs in July" chip. 9 Oct is partial.
- **Caption:** "45 PRs opened on 7 October alone."

**Chart spec: "commits per day"** (optional, small)
- **Type:** a sparkline or calendar heat strip.
- **Data:** `pace.commits_by_day_main[]`.

**AI spend card:**
> Letting bots play hundreds of sessions sounds expensive. It isn't: the playtest batches documented so far cost about **$`ai_spend.documented_total_usd`** in total, roughly **$0.09–0.11 per 10-turn run**. Playtest has a daily cap of **$`ai_spend.playtest_day_cap_usd`**, and we haven't come close.

**Chart spec: "where the AI money went"**
- **Type:** a horizontal bar chart.
- **Data:** `ai_spend.documented_items_usd[]`.
- **Gap line under the chart:** "Not shown: production AI spend (see /admin/costs) and the bots' own running costs; neither is in the docs yet." (`ai_spend.gaps`)

**Closing line:**
> One human yes on every change, three bots that never get tired, and a paper trail for every decision. That's how Tales Forge gets built.

---

## Image ideas

- **Bot avatars (illustrated):** a consistent set in a warm, slightly painterly fantasy-tavern style, head and shoulders, round crop.
  - *Fredrik:* a human figure at a big oak table with a seal or stamp (the one who approves).
  - *Case:* a calm planner with a map and compass and blueprint lines in the background.
  - *Bobby:* a tinkerer-smith at a small forge with a laptop, sparks shaped like `|>` (Elixir's pipe).
  - *Gentry:* a sharp-eyed inspector with a magnifying glass and a mischievous grin, maybe a red quill for marking faults.
  - *Personas:* the same style, a small token each. Hawk with a sword, Paul with a theatre mask, Lotta with a hand mirror, Lars with a quest map, Ronny with a sack of gold (greyed).
- **Architecture diagram:** clean SVG, three call-type colours, small icons (a person, a lightning bolt for LiveView, a sieve or lens for Jev, gears for Elixir, a quill for the GM, a scroll for prose).
- **Flow animation:** a d20 token rolling along a path through 11 stations, with the "Fredrik's OK" station drawn as a wax seal.
- **Hero art (optional):** a tavern table where three small bots and a human lean over a map of Tin Valley.

## Build notes for Bobby

- All copy and numbers come from this file and `data.json`. Read `data.json` at build or compile time; don't hard-code numbers in templates.
- `null` in `data.json` means "not measured yet". Render that text, never a zero.
- No secrets on the page. `infrastructure.keys` deliberately says only where keys live.
- Behind the existing GitHub team sign-in. Check it at 320, 390 and 1280 px, in dark mode, and with `prefers-reduced-motion`. Gentry will.
