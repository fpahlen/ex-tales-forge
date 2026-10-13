# Workflow product boundary

Source of truth for the Workflow split (board card
[Workflow split 1/5: Product boundary](https://tales-forge.fly.dev/team#idea-20e31daf-4c74-4bc9-b7c9-c2cf819161f9)).
Decision log: tales-forge-docs `docs/decisions.md`, 2026-10-13, slug
`2026-10-13-workflow-split-1-5-product-boundary`.

The team tools are the product **Workflow**. The game (Tales Forge) is a
client of Workflow. Cards 2 to 5 use this list. Do not reopen the boundary
on those cards; change this file and the board card first.

## Workflow owns

1. `ExTalesForge.Board` and `/internal/board/*`
2. `ExTalesForge.Chat` and `TeamChatLive`
3. `ExTalesForge.WorkLog` and `TeamWorkLogLive`
4. `ExTalesForge.PrFeed` and `TeamPrFeedLive`
5. `ExTalesForge.Board.Goals` and the goals UI
6. `TeamLive`, `TeamPresentationLive` and the team components
7. `ExTalesForge.TeamOnline` for founders on `/team`
8. Team images under `ExTalesForge.Images` that the team page stores
9. Workflow docs under `/admin/docs` (team and board docs)

## Game (Tales Forge) owns

1. `ExTalesForge.Costs` and `/admin/operate/costs`
2. `ExTalesForge.Online` for players in the game
3. Play and test pages under `/admin/play`
4. Game sessions, characters, NPCs, world packs and turn code
5. LLM and AI call modules that serve the game
6. Collab decisions (`ExTalesForge.Collab`, `/admin/founders/decisions`)
7. Founder surveys (`ExTalesForge.Surveys`, `/admin/founders/survey*`)
8. RPG game docs under `/admin/docs`
9. The admin home shell at `/admin` (`AdminSections`) as the game hub

## Shared wiring for now

Cards 3 to 5 move these:

1. `ExTalesForge.Repo`
2. The router and `application.ex`
3. `ExTalesForge.AdminAuth` and GitHub team sign-in
4. `ExTalesForge.AppRole` home map

## Presentation Tales Forge text (for card 2)

Workflow keeps the rest of the presentation. Card 2 moves this Tales Forge
text into team content:

- Hero title: "How Tales Forge gets built"
- Section `team`: opening line that names Tales Forge
- Section `wired`: sign-in line that names the Tales Forge team
- Section `infrastructure`: "Tales Forge runs as two apps…"
- Header product link in `team_layout.ex` ("Tales Forge")
- Call-types copy that names Tales Forge in `team_call_types.ex`

## Founder answers (2026-10-13)

- Collab decisions stay with Tales Forge.
- Founder surveys stay with Tales Forge.
- `/admin/docs` split by content: RPG game docs with the game; Workflow docs
  with Workflow.
- The admin home shell at `/admin` stays with the game as a hub.
