---
title: "Design: Decision queue and shared docs"
updated: 2026-10-06
source: https://docs.google.com/document/d/10_XwZK5a0_F4MAuL8LEMYaNUVGHwhVpDtb7Lq-gC9WE/edit
---

# Tales Forge – Design: Decision queue and shared docs

**Type:** Design note (day-one collaboration tool)  
**Date:** 2026-10-05  
**Status:** Proposed direction (hosting decided: inside the game admin)  
**Context:** Five founders; bots build 24/7; founders decide what next. Nobody assigns tasks; people self-assign. Prefer a system we own over SaaS. Secure-ish, usable by humans and agents.

---

## 1. Problem

The outer loop (founders as product owners) needs a single ranked place for open decisions and the docs that inform them. Today the ranked list lives in [`roadmap-2027.md`](roadmap-2027.md) and docs sit in Google Drive / `/workspace/tales-forge-plan/`. That works for now, but agents cannot propose cleanly, history is thin, and Drive is a temporary home until something better exists.

Day-one scope is **only** the decision queue and shared docs. Bot result feeds and dashboards come later.

## 2. Principle: Git is the source of truth

Same pattern as game data as Markdown: a **private** repo (e.g. `tales-forge-docs`, or `/docs` and `/decisions` folders in an existing private repo) holds:

- Markdown docs under `docs/`
- One Markdown file per decision under `decisions/`, with YAML front matter

Humans and bots change things through commits and PRs. Git history is the audit log. A small LiveView app indexes the repo into Postgres for a live UI; it never becomes a second source of truth without writing back to Git.

### Decision file front matter

| Field | Purpose |
|---|---|
| `id` | Stable slug (e.g. `d-001-elixir-foundation`) |
| `title` | Short title |
| `rank` | Integer; lowest number = most important |
| `status` | `open` \| `discussing` \| `decided` \| `superseded` |
| `options` | List of options under consideration |
| `decision` | Chosen option (when decided) |
| `rationale` | Why |
| `decided_at` | ISO date (when decided) |
| `links` | Related PRs, docs, issues |
| `interested` | People who self-select (not owners) |

Body: discussion notes, context, links to longer docs. Seed from the twelve ranked decisions already in [`roadmap-2027.md`](roadmap-2027.md).

## 3. UI: a section inside the game's admin

**Decided (2026-10-05):** the tool lives as a section of the game's existing Ash / Phoenix LiveView admin in `ex-tales-forge`, not as a separate app. It reuses the game's deploy, Postgres and Ash patterns, and adds GitHub OAuth limited to the five founders on top of the game's auth.

The UI shows:

1. **Ranked queue** — drag to rerank; writes a commit/PR updating `rank` fields  
2. **Decision page** — options, discussion thread, record-outcome form (human-only)  
3. **Docs browser** — tree + full-text search over indexed Markdown  

Updates live via LiveView as the index refreshes from Git (webhook or poll).

## 4. Agent access

Expose an **MCP server and/or JSON API** with tools such as:

- `list_decisions`, `get_decision`, `propose_decision`, `comment`
- `record_outcome` — **human-only**; agents must never call it successfully
- `search_docs`, `get_doc`, `propose_doc_change`

Agents **propose**; humans **decide**. Proposals land as PRs or as `open` / `discussing` files pending human merge and outcome.

## 5. Security

- GitHub OAuth limited to an **allowlist of the five founders**
- One **scoped, revocable token per bot**; separate **read** vs **propose** scopes
- Agents cannot mark a decision `decided`
- Everything audit-logged (who/what/when; Git + app log)
- Private repo; optionally behind **Tailscale**; no public access
- Secrets live outside the repo (Fly secrets / env)

**Keeping the admin apart from the player side.** Because this lives inside the game app, the admin section gets its own router pipeline and scopes, separate from player-facing routes. Founder sessions and bot tokens are only valid in that pipeline. Agent tokens are scoped to decisions and docs and have no access to player accounts, characters or sessions. If possible, the admin routes are served only on the internal or Tailscale side, never on the public hostname.

## 6. Decision lifecycle

**States (prose):**

1. **open** — in the ranked queue; needs attention; no active discussion yet, or discussion paused  
2. **discussing** — comments / options being refined; still open for change  
3. **decided** — outcome and rationale recorded; file updated; interested people notified  
4. **superseded** — a later decision replaces this one; link both ways  

Typical path: `open` → `discussing` → `decided`. Any non-decided state can move to `superseded` if a new decision replaces it. Reopening a decided item creates a new decision (or explicitly reopens with a new rank) so history stays clear.

**Bot escalation into the queue:**

1. Inner loop finds something that needs judgment (not a clear-cut fix).  
2. Bot calls `propose_decision` (or opens a PR adding a decision file) with context, options if known, and links to the finding.  
3. New file lands as `status: open` at the bottom of the rank list (or a suggested rank); humans drag to promote.  
4. Founders discuss, self-select on `interested`, then a human records the outcome.

## 7. MVP cut (ordered by importance)

No owners or names — only ordered work packages:

1. **Repo layout + decision file format + seed the 12 decisions** from [`roadmap-2027.md`](roadmap-2027.md)  
2. **Read-only LiveView** queue and docs browser behind GitHub login (allowlist)  
3. **Comments and drag-to-rerank** (write-back via commit/PR)  
4. **MCP server / JSON API** for agents (list, get, propose, comment, search; no record_outcome)  
5. **Record decision + notifications** to interested people  

**Explicitly out for now:** bot result feeds, persona scorecard dashboards, task boards, SaaS sync, public access, migrating every historical Drive chat.

## 8. Open questions

- Do existing Google Drive docs migrate into the repo, or stay linked until rewritten?  
- Notifications: email, Discord, Signal, or GitHub only?  
- How do chat conversations with assistants get summarised into decision files without noise?  

**Note:** the Google Drive folder remains the temporary home for founder docs until this system exists. Do not treat Drive as the long-term source of truth.

## 9. Success look

Any founder (or allowed agent) can see the next most important open decision, open the related docs, propose a change via PR or MCP, and leave a trail that Git and the app both record. The twelve seeded decisions are the first queue; new escalations from bots join the same list.
