# Decision file schema

Each file under `decisions/` is Markdown with YAML front matter.

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

Body: discussion notes, context, links to longer docs.

**Lifecycle:** `open` → `discussing` → `decided`. Superseded decisions link both ways. Agents may propose and comment; only humans set `status: decided`.
