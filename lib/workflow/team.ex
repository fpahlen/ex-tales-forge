defmodule Workflow.Team do
  @moduledoc """
  The team config of Workflow, the team tools (board, team page, mentions,
  `TalesForge.TeamOnline`). A plain struct with no IO.

  Workflow code has no team names. Each Workflow function that needs a name,
  a bot or a label gets this struct as an argument. Only the edge reads the
  source (`Workflow.Team.Source`): a LiveView, a controller, a worker or a
  context function that also does IO.

  One Workflow app serves one team, so the data has no team id.

  Fields:

    * `product_name`: the product that the team builds
    * `repo_url`: the code repository of the product
    * `docs_repo`: the `owner/name` of the docs repository (decision log)
    * `user_agent`: the user agent of the GitHub calls of the board
    * `decision_email`: the author email of a decision log entry when the
      founder has no email
    * `founders`: `t:founder/0`, in board order
    * `bots`: `t:bot/0`, in board order
    * `column_labels`: the label of each of the seven board columns
    * `goals`: the seed goals (`key`, `title`); the live goals are rows in the
      database (`TalesForge.Board.Goal`)
    * `jobs`: `t:job/0`, the scheduled jobs. This list is the only schedule
      source: the Workflow Oban instance builds its cron table from it
      (`crontab/1`), and the Upcoming panel on the team page shows it
    * `content`: the presentation text by key (`text/2`)
  """

  @typedoc """
  A bot role. The `refiner` refines cards in Refining. The `builder` builds
  cards in Building and links the PRs. The `checker` checks the build on
  playtest.
  """
  @type role :: :refiner | :builder | :checker

  @typedoc "A bot: `id` is the atom of the bot API and the `bot:<id>` actor."
  @type bot :: %{id: atom(), name: String.t(), role: role()}

  @typedoc """
  A founder: `handle` is the @mention handle, `github` the GitHub login.
  `emails` holds the sign-in emails of the founder (lower case), so a log
  email gets the founder's name.
  `inbox` holds the ids of the inbox rules for this founder
  (`Workflow.Inbox.rules/0`). An empty list gives no inbox.
  """
  @type founder :: %{
          name: String.t(),
          handle: String.t(),
          github: String.t() | nil,
          emails: [String.t()],
          inbox: [String.t()]
        }

  @typedoc """
  A scheduled job. `cron` is a cron line in UTC (Oban cron, no time zone).
  `owner` is `"code"` for a job that plain code does (`worker` is the Oban
  worker module, it starts no bot), or the id of the bot or the handle of
  the founder who does the job. `limit_min` is the time limit of one run in
  minutes.
  """
  @type job :: %{
          id: String.t(),
          name: String.t(),
          cron: String.t(),
          owner: String.t(),
          worker: module() | nil,
          limit_min: pos_integer()
        }

  @type t :: %__MODULE__{
          product_name: String.t(),
          repo_url: String.t(),
          docs_repo: String.t(),
          user_agent: String.t(),
          decision_email: String.t(),
          founders: [founder()],
          bots: [bot()],
          column_labels: %{String.t() => String.t()},
          goals: [%{key: String.t(), title: String.t()}],
          jobs: [job()],
          content: %{String.t() => String.t()}
        }

  defstruct product_name: "",
            repo_url: "",
            docs_repo: "",
            user_agent: "workflow-board",
            decision_email: "board@workflow.invalid",
            founders: [],
            bots: [],
            column_labels: %{},
            goals: [],
            jobs: [],
            content: %{}

  @roles ~w(refiner builder checker)a
  @states ~w(ideas refining check building done parked archived)

  @doc """
  The team from the decoded `workflow` block of the team data and the decoded
  content map. Pure. Raises on a missing bot role or column label, so a broken
  file fails the build.

      iex> team = Workflow.Team.example()
      iex> {team.product_name, Workflow.Team.bot(team, :builder)}
      {"Example Product", :bram}
  """
  @spec from_map(map(), map()) :: t()
  def from_map(%{} = w, content \\ %{}) do
    team = %__MODULE__{
      product_name: Map.fetch!(w, "product_name"),
      repo_url: Map.fetch!(w, "repo_url"),
      docs_repo: Map.fetch!(w, "docs_repo"),
      user_agent: Map.get(w, "user_agent", "workflow-board"),
      decision_email: Map.get(w, "decision_email", "board@workflow.invalid"),
      founders:
        for f <- Map.fetch!(w, "founders") do
          name = Map.fetch!(f, "name")

          %{
            name: name,
            handle: Map.get(f, "handle") || plain(name),
            github: f["github"],
            emails: f |> Map.get("emails", []) |> Enum.map(&String.downcase/1),
            inbox: Map.get(f, "inbox", [])
          }
        end,
      bots:
        for b <- Map.fetch!(w, "bots") do
          %{
            id: b |> Map.fetch!("id") |> String.to_atom(),
            name: Map.fetch!(b, "name"),
            role: b |> Map.fetch!("role") |> role!()
          }
        end,
      column_labels: Map.fetch!(w, "column_labels"),
      goals: for(g <- Map.get(w, "goals", []), do: %{key: g["key"], title: g["title"]}),
      jobs: for(j <- Map.get(w, "jobs", []), do: job!(j)),
      content: content
    }

    Enum.each(@roles, &bot(team, &1))
    Enum.each(team.jobs, &owner!(team, &1))

    case Enum.reject(@states, &Map.has_key?(team.column_labels, &1)) do
      [] -> team
      missing -> raise ArgumentError, "no column label for #{inspect(missing)}"
    end
  end

  defp job!(j) do
    cron = Map.fetch!(j, "cron")
    _ = Oban.Cron.Expression.parse!(cron)
    owner = Map.fetch!(j, "owner")
    worker = j["worker"] && Module.concat([j["worker"]])

    if owner == "code" and is_nil(worker),
      do: raise(ArgumentError, "the code job #{inspect(j["id"])} has no worker")

    %{
      id: Map.fetch!(j, "id"),
      name: Map.fetch!(j, "name"),
      cron: cron,
      owner: owner,
      worker: worker,
      limit_min: Map.get(j, "limit_min", 30)
    }
  end

  defp owner!(team, %{owner: owner, id: id}) do
    unless owner == "code" or bot_id(team, owner) != nil or owner in handles(team),
      do: raise(ArgumentError, "the job #{inspect(id)} has an unknown owner #{inspect(owner)}")
  end

  defp role!(r) when r in ~w(refiner builder checker), do: String.to_atom(r)
  defp role!(r), do: raise(ArgumentError, "unknown bot role #{inspect(r)}")

  @doc """
  A small team with neutral names, for doc examples and tests.
  """
  @spec example() :: t()
  def example do
    from_map(
      %{
        "product_name" => "Example Product",
        "repo_url" => "https://example.com/org/product",
        "docs_repo" => "org/product-docs",
        "founders" => [
          %{"name" => "Ada", "github" => "ada-gh", "inbox" => ["mention"]},
          %{"name" => "Örjan", "github" => "orjan-gh", "emails" => ["orjan.x@x.se"]},
          %{"name" => "Lin"}
        ],
        "bots" => [
          %{"id" => "rita", "name" => "Rita", "role" => "refiner"},
          %{"id" => "bram", "name" => "Bram", "role" => "builder"},
          %{"id" => "quill", "name" => "Quill", "role" => "checker"}
        ],
        "column_labels" => %{
          "ideas" => "Ideas",
          "refining" => "Refining (Rita)",
          "check" => "Founder check",
          "building" => "Building (Bram)",
          "done" => "Done",
          "parked" => "Parked",
          "archived" => "Archive"
        },
        "jobs" => [
          %{
            "id" => "sweep",
            "name" => "Sweep",
            "cron" => "*/15 * * * *",
            "owner" => "code",
            "worker" => "Example.SweepWorker"
          },
          %{"id" => "check", "name" => "Check", "cron" => "0 7 * * 1-5", "owner" => "quill"}
        ]
      },
      %{"hello" => "Hello from {product}."}
    )
  end

  @doc """
  The id of the bot with `role`.

      iex> Workflow.Team.bot(Workflow.Team.example(), :refiner)
      :rita
  """
  @spec bot(t(), role()) :: atom()
  def bot(%__MODULE__{bots: bots}, role) do
    case Enum.find(bots, &(&1.role == role)) do
      %{id: id} -> id
      nil -> raise ArgumentError, "the team has no #{role} bot"
    end
  end

  @doc """
  The display name of a bot, by role or by id.

      iex> team = Workflow.Team.example()
      iex> {Workflow.Team.bot_name(team, :checker), Workflow.Team.bot_name(team, :bram)}
      {"Quill", "Bram"}
  """
  @spec bot_name(t(), role() | atom()) :: String.t()
  def bot_name(%__MODULE__{bots: bots} = team, role_or_id) do
    id = if role_or_id in @roles, do: bot(team, role_or_id), else: role_or_id
    Enum.find_value(bots, Atom.to_string(id), &(&1.id == id && &1.name))
  end

  @doc """
  The bot ids, in board order.

      iex> Workflow.Team.bot_ids(Workflow.Team.example())
      [:rita, :bram, :quill]
  """
  @spec bot_ids(t()) :: [atom()]
  def bot_ids(%__MODULE__{bots: bots}), do: Enum.map(bots, & &1.id)

  @doc """
  The bot ids as strings, in board order (the @mention handles of the bots).

      iex> Workflow.Team.bot_handles(Workflow.Team.example())
      ["rita", "bram", "quill"]
  """
  @spec bot_handles(t()) :: [String.t()]
  def bot_handles(team), do: team |> bot_ids() |> Enum.map(&Atom.to_string/1)

  @doc """
  The bot id of a handle or of a `bot:<id>` actor, or nil.

      iex> team = Workflow.Team.example()
      iex> {Workflow.Team.bot_id(team, "bot:rita"), Workflow.Team.bot_id(team, "quill"), Workflow.Team.bot_id(team, "nobody")}
      {:rita, :quill, nil}
  """
  @spec bot_id(t(), String.t() | nil) :: atom() | nil
  def bot_id(team, "bot:" <> id), do: bot_id(team, id)

  def bot_id(team, id) when is_binary(id),
    do: Enum.find(bot_ids(team), &(Atom.to_string(&1) == id))

  def bot_id(_team, _id), do: nil

  @doc """
  The role of the bot with the id `id` (a string or an atom), or nil.

      iex> team = Workflow.Team.example()
      iex> {Workflow.Team.role(team, "rita"), Workflow.Team.role(team, :quill), Workflow.Team.role(team, "founders")}
      {:refiner, :checker, nil}
  """
  @spec role(t(), String.t() | atom()) :: role() | nil
  def role(%__MODULE__{bots: bots}, id) do
    id = to_string(id)
    Enum.find_value(bots, &(Atom.to_string(&1.id) == id && &1.role))
  end

  @doc """
  The `bot:<id>` actor string of the bot with `role`.

      iex> Workflow.Team.actor(Workflow.Team.example(), :builder)
      "bot:bram"
  """
  @spec actor(t(), role()) :: String.t()
  def actor(team, role), do: "bot:#{bot(team, role)}"

  @doc """
  The `owner/name` of the code repository.

      iex> Workflow.Team.repo(Workflow.Team.example())
      "org/product"
  """
  @spec repo(t()) :: String.t()
  def repo(%__MODULE__{repo_url: url}),
    do: url |> URI.parse() |> Map.get(:path) |> to_string() |> String.trim("/")

  @doc """
  The @mentions of the bots, for a help line.

      iex> Workflow.Team.bot_mentions(Workflow.Team.example())
      "@rita, @bram or @quill"
  """
  @spec bot_mentions(t()) :: String.t()
  def bot_mentions(team) do
    case Enum.map(bot_handles(team), &("@" <> &1)) do
      [] -> ""
      [one] -> one
      all -> Enum.join(Enum.drop(all, -1), ", ") <> " or " <> List.last(all)
    end
  end

  @doc """
  A count as a word, for counts up to ten.

      iex> {Workflow.Team.count_word(3), Workflow.Team.count_word(12)}
      {"three", "12"}
  """
  @spec count_word(non_neg_integer()) :: String.t()
  def count_word(n) when n in 0..10,
    do: Enum.at(~w(zero one two three four five six seven eight nine ten), n)

  def count_word(n), do: Integer.to_string(n)

  @doc """
  A job by id, or nil.

      iex> Workflow.Team.job(Workflow.Team.example(), "check").owner
      "quill"
  """
  @spec job(t(), String.t()) :: job() | nil
  def job(%__MODULE__{jobs: jobs}, id), do: Enum.find(jobs, &(&1.id == id))

  @doc """
  True when plain code does the job (no bot).

      iex> team = Workflow.Team.example()
      iex> {Workflow.Team.code_job?(Workflow.Team.job(team, "sweep")), Workflow.Team.code_job?(Workflow.Team.job(team, "check"))}
      {true, false}
  """
  @spec code_job?(job()) :: boolean()
  def code_job?(%{owner: owner}), do: owner == "code"

  @doc """
  The Oban cron table of the code jobs: one `{cron, worker, opts}` entry for
  each job, with the job id in the args. The cron lines are in UTC.

      iex> Workflow.Team.crontab(Workflow.Team.example())
      [{"*/15 * * * *", Example.SweepWorker, [args: %{"job_id" => "sweep"}]}]
  """
  @spec crontab(t()) :: [{String.t(), module(), keyword()}]
  def crontab(%__MODULE__{jobs: jobs}) do
    for job <- jobs, code_job?(job), do: {job.cron, job.worker, [args: %{"job_id" => job.id}]}
  end

  @doc """
  The next run of each job after `now`, in UTC, soonest first.

      iex> Workflow.Team.example()
      ...> |> Workflow.Team.next_runs(~U[2026-10-16 07:10:00Z])
      ...> |> Enum.map(fn {job, at} -> {job.id, at} end)
      [{"sweep", ~U[2026-10-16 07:15:00Z]}, {"check", ~U[2026-10-19 07:00:00Z]}]
  """
  @spec next_runs(t(), DateTime.t()) :: [{job(), DateTime.t()}]
  def next_runs(%__MODULE__{jobs: jobs}, %DateTime{} = now) do
    jobs
    |> Enum.map(&{&1, next_at(&1, now)})
    |> Enum.sort_by(fn {_job, at} -> at end, DateTime)
  end

  @doc """
  The next run of `job` after `now`, in UTC.

      iex> job = Workflow.Team.job(Workflow.Team.example(), "check")
      iex> Workflow.Team.next_at(job, ~U[2026-10-16 06:59:30Z])
      ~U[2026-10-16 07:00:00Z]
  """
  @spec next_at(job(), DateTime.t()) :: DateTime.t()
  def next_at(%{cron: cron}, %DateTime{} = now) do
    cron |> Oban.Cron.Expression.parse!() |> Oban.Cron.Expression.next_at(now)
  end

  @doc """
  The founder names, in board order (accents kept).

      iex> Workflow.Team.founder_names(Workflow.Team.example())
      ["Ada", "Örjan", "Lin"]
  """
  @spec founder_names(t()) :: [String.t()]
  def founder_names(%__MODULE__{founders: founders}), do: Enum.map(founders, & &1.name)

  @doc """
  The founder @mention handles: the name in lower case without accents.

      iex> Workflow.Team.handles(Workflow.Team.example())
      ["ada", "orjan", "lin"]
  """
  @spec handles(t()) :: [String.t()]
  def handles(%__MODULE__{founders: founders}), do: Enum.map(founders, & &1.handle)

  @doc """
  The map of GitHub login (lower case) to founder handle.

      iex> Workflow.Team.github_handles(Workflow.Team.example())
      %{"ada-gh" => "ada", "orjan-gh" => "orjan"}
  """
  @spec github_handles(t()) :: %{String.t() => String.t()}
  def github_handles(%__MODULE__{founders: founders}) do
    for %{github: gh, handle: h} <- founders,
        is_binary(gh),
        into: %{},
        do: {String.downcase(gh), h}
  end

  @doc """
  The label of a board column. All teams use the same seven columns.

      iex> Workflow.Team.label(Workflow.Team.example(), "refining")
      "Refining (Rita)"
      iex> Workflow.Team.label(Workflow.Team.example(), "other")
      "other"
  """
  @spec label(t(), String.t()) :: String.t()
  def label(%__MODULE__{column_labels: labels}, state), do: Map.get(labels, state, state)

  @doc """
  The presentation text of `key`. `{product}` becomes the product name.
  Raises on an unknown key, so a missing text fails the tests.

      iex> Workflow.Team.text(Workflow.Team.example(), "hello")
      "Hello from Example Product."
  """
  @spec text(t(), String.t()) :: String.t()
  def text(%__MODULE__{content: content, product_name: product}, key) do
    content |> Map.fetch!(key) |> String.replace("{product}", product)
  end

  @doc """
  A name in lower case without accents and other non-letters (the handle form).

      iex> Workflow.Team.plain("Örjan-Ö")
      "orjano"
  """
  @spec plain(String.t()) :: String.t()
  def plain(name) do
    name
    |> String.downcase()
    |> :unicode.characters_to_nfd_binary()
    |> String.replace(~r/[^a-z]/u, "")
  end
end
