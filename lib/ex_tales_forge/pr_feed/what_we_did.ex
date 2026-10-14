defmodule TalesForge.PrFeed.WhatWeDid do
  @moduledoc """
  The "What have we done" panel on `/team`: the pull requests merged in the
  product repo in the last #{3} days (Europe/Stockholm), as short theme
  bullets. Each bullet links to its pull requests.

  - `window/4` is pure. It takes the merged pull requests of the PR feed
    (`TalesForge.PrFeed.recent_merged/2`) and keeps the ones of the product
    repo (the team config's `repo_url`, `Workflow.Team`) that were merged
    since midnight #{3 - 1} days before today, Europe/Stockholm time.
  - `summary/3` makes the bullets with one model call
    (`TalesForge.PrFeed.WhatWeDidLLM`, or the function in the app env
    `:what_we_did_llm`). The result is cached for each Stockholm day and each
    set of pull request numbers, so a page view costs no new call.
  - When the call fails, gives a bad answer, or is off (config
    `:ex_tales_forge, #{inspect(__MODULE__)}, ai: false`, WHAT_WE_DID_AI=false),
    the panel shows the plain pull request titles (`fallback/1`).
  """

  alias TalesForge.PrFeed

  @zone "Europe/Stockholm"
  @days 3
  @max_bullets 7

  @system """
  You write the "What have we done" panel for the team page of a small team.
  You get the pull requests that the team merged in the last days, one for each
  line, as "#<number> <title>".

  Write #{@max_bullets} or fewer short theme bullets. Each bullet joins related pull
  requests into one plain sentence about what is new or better.
  Rules:
  - Write in ASD-STE100 Simplified Technical English: short sentences, active
    voice, simple words, present or past tense.
  - Use positive framing: say what works now and what is new.
  - Start each bullet with the thing that is new or better, for example
    "Chat threads notify each participant." Never start with "The team" or
    "We", and never write "The team".
  - Write no @ handles and no names of people.
  - "Workflow" is the team tools. Never call Workflow a game.
  - Use only facts from the titles. Do not guess.
  - Put the numbers of the pull requests of each bullet in "prs". Use only the
    numbers that you got. Each pull request goes in one bullet.
  Answer with JSON only: {"bullets": [{"text": "...", "prs": [123, 124]}]}.
  """

  @typedoc "A pull request link of a bullet."
  @type pr_link :: %{number: pos_integer(), url: String.t() | nil}

  @typedoc "One bullet: a short text and the pull requests it is about."
  @type bullet :: %{text: String.t(), prs: [pr_link()]}

  @typedoc """
  The panel: the bullets, `:ai` (from the model) or `:titles` (the plain
  titles), the number of pull requests and the first day of the window.
  """
  @type t :: %{
          source: :ai | :titles,
          bullets: [bullet()],
          count: non_neg_integer(),
          since: Date.t()
        }

  @doc "The number of days in the window."
  @spec days() :: pos_integer()
  def days, do: @days

  @doc "The system prompt of the model call."
  @spec system_prompt() :: String.t()
  def system_prompt, do: @system

  @doc """
  The pull requests of the window, newest first: merged since midnight
  #{@days - 1} days before the day of `now` (Europe/Stockholm), and their URL
  is in `repo_url`.

      iex> now = ~U[2026-10-14 08:00:00Z]
      iex> repo = "https://github.com/org/product"
      iex> merged = [
      ...>   %{number: 3, title: "C", url: repo <> "/pull/3", merged_at: ~U[2026-10-14 07:00:00Z]},
      ...>   %{number: 2, title: "B", url: repo <> "/pull/2", merged_at: ~U[2026-10-11 22:30:00Z]},
      ...>   %{number: 1, title: "A", url: repo <> "/pull/1", merged_at: ~U[2026-10-11 21:30:00Z]},
      ...>   %{number: 9, title: "X", url: "https://github.com/org/other/pull/9", merged_at: ~U[2026-10-14 07:00:00Z]}
      ...> ]
      iex> TalesForge.PrFeed.WhatWeDid.window(merged, repo, now) |> Enum.map(& &1.number)
      [3, 2]
  """
  @spec window([PrFeed.merged()], String.t(), DateTime.t(), pos_integer()) :: [PrFeed.merged()]
  def window(merged, repo_url, %DateTime{} = now, days \\ @days) do
    since = since_utc(now, days)
    prefix = String.trim_trailing(repo_url || "", "/") <> "/pull/"

    merged
    |> Enum.filter(fn pr ->
      is_binary(pr.url) and String.starts_with?(pr.url, prefix) and
        DateTime.compare(pr.merged_at, since) != :lt
    end)
    |> Enum.sort_by(&DateTime.to_unix(&1.merged_at), :desc)
  end

  @doc """
  The first day of the window (Europe/Stockholm).

      iex> TalesForge.PrFeed.WhatWeDid.since_date(~U[2026-10-14 08:00:00Z])
      ~D[2026-10-12]
  """
  @spec since_date(DateTime.t(), pos_integer()) :: Date.t()
  def since_date(%DateTime{} = now, days \\ @days),
    do: now |> local_date() |> Date.add(-(days - 1))

  defp since_utc(now, days) do
    now
    |> since_date(days)
    |> DateTime.new!(~T[00:00:00], @zone, TimeZoneInfo.TimeZoneDatabase)
    |> DateTime.shift_zone!("Etc/UTC", TimeZoneInfo.TimeZoneDatabase)
  end

  defp local_date(now),
    do: now |> DateTime.shift_zone!(@zone, TimeZoneInfo.TimeZoneDatabase) |> DateTime.to_date()

  @doc """
  The user prompt: one line for each pull request, "#<number> <title>".

      iex> TalesForge.PrFeed.WhatWeDid.prompt([%{number: 3, title: " Add the inn "}])
      "#3 Add the inn"
  """
  @spec prompt([PrFeed.merged()]) :: String.t()
  def prompt(prs), do: Enum.map_join(prs, "\n", &"##{&1.number} #{String.trim(&1.title)}")

  @doc """
  The fallback: one bullet for each pull request, with its title.

      iex> TalesForge.PrFeed.WhatWeDid.fallback([%{number: 3, title: "Add the inn", url: "u3"}])
      [%{text: "Add the inn", prs: [%{number: 3, url: "u3"}]}]
  """
  @spec fallback([PrFeed.merged()]) :: [bullet()]
  def fallback(prs), do: Enum.map(prs, &%{text: String.trim(&1.title), prs: [link(&1)]})

  @doc """
  Decodes the model's answer into bullets. A bullet without text or without a
  known pull request is left out, and an unknown number is dropped. Nil when
  no bullet is left.

      iex> prs = [%{number: 3, title: "Add the inn", url: "u3"}, %{number: 4, title: "Fix", url: "u4"}]
      iex> TalesForge.PrFeed.WhatWeDid.decode(%{"bullets" => [
      ...>   %{"text" => " The inn is new. ", "prs" => [3, 99]},
      ...>   %{"text" => "", "prs" => [4]},
      ...>   %{"text" => "Ghost.", "prs" => [99]}]}, prs)
      [%{text: "The inn is new.", prs: [%{number: 3, url: "u3"}]}]
      iex> TalesForge.PrFeed.WhatWeDid.decode(%{"bullets" => []}, prs)
      nil
  """
  @spec decode(term(), [PrFeed.merged()]) :: [bullet()] | nil
  def decode(%{"bullets" => bullets}, prs) when is_list(bullets) do
    by_number = Map.new(prs, &{&1.number, &1})

    bullets
    |> Enum.flat_map(&bullet(&1, by_number))
    |> Enum.take(@max_bullets)
    |> case do
      [] -> nil
      list -> list
    end
  end

  def decode(_reply, _prs), do: nil

  defp bullet(%{"text" => text, "prs" => numbers}, by_number)
       when is_binary(text) and is_list(numbers) do
    links =
      numbers
      |> Enum.filter(&Map.has_key?(by_number, &1))
      |> Enum.uniq()
      |> Enum.map(&link(by_number[&1]))

    text = text |> String.trim() |> drop_team_subject()
    if text == "" or links == [], do: [], else: [%{text: text, prs: links}]
  end

  defp bullet(_other, _by_number), do: []

  @doc """
  Removes a leading "The team" that the model can write, and makes the
  next letter upper case.

      iex> TalesForge.PrFeed.WhatWeDid.drop_team_subject("The team adds chat threads.")
      "Adds chat threads."
      iex> TalesForge.PrFeed.WhatWeDid.drop_team_subject("Chat threads are new.")
      "Chat threads are new."
  """
  @spec drop_team_subject(String.t()) :: String.t()
  def drop_team_subject(text) do
    case Regex.run(~r/^the team\s+(.*)$/isu, text) do
      [_, rest] ->
        {first, rest} = String.split_at(rest, 1)
        String.upcase(first) <> rest

      nil ->
        text
    end
  end

  defp link(pr), do: %{number: pr.number, url: pr.url}

  @doc """
  The panel for the merged pull requests of the PR feed at `now`. Options:

  - `:repo_url`: the product repo (default: the team config's `repo_url`).
  - `:llm`: the model call, `(system, user, opts -> {:ok, map} | {:error, term})`.
  - `:ai`: false turns the model call off.

  The result is cached for each Stockholm day and set of pull request
  numbers. A failed call is cached too, so a broken model costs no call on
  each page view. No pull requests: no call.
  """
  @spec summary([PrFeed.merged()], DateTime.t(), keyword()) :: t()
  def summary(merged, %DateTime{} = now, opts \\ []) do
    prs = window(merged, Keyword.get_lazy(opts, :repo_url, &repo_url/0), now)
    key = key(prs, now)

    case cached(key) do
      %{} = hit ->
        hit

      nil ->
        :global.trans({__MODULE__, :summary}, fn ->
          cached(key) || store(key, build(prs, now, opts))
        end)
    end
  end

  @doc """
  The cached panel for the merged pull requests at `now`, else the plain
  titles. It never calls the model (for the first render of the page).
  """
  @spec cached_or_titles([PrFeed.merged()], DateTime.t(), keyword()) :: t()
  def cached_or_titles(merged, %DateTime{} = now, opts \\ []) do
    prs = window(merged, Keyword.get_lazy(opts, :repo_url, &repo_url/0), now)
    cached(key(prs, now)) || titles(prs, now)
  end

  @doc "Clears the cache (tests)."
  @spec clear_cache() :: :ok
  def clear_cache do
    :persistent_term.erase({__MODULE__, :cache})
    :ok
  end

  defp build([], now, _opts), do: titles([], now)

  defp build(prs, now, opts) do
    with true <- Keyword.get_lazy(opts, :ai, &ai?/0),
         {:ok, reply} <- call(Keyword.get_lazy(opts, :llm, &llm/0), prs),
         bullets when is_list(bullets) <- decode(reply, prs) do
      %{source: :ai, bullets: bullets, count: length(prs), since: since_date(now)}
    else
      _ -> titles(prs, now)
    end
  end

  defp call(llm, prs) do
    llm.(@system, prompt(prs), [])
  rescue
    error -> {:error, error}
  end

  defp titles(prs, now),
    do: %{source: :titles, bullets: fallback(prs), count: length(prs), since: since_date(now)}

  defp key(prs, now), do: {local_date(now), Enum.map(prs, & &1.number) |> Enum.sort()}

  # One entry: a new day or a new merge replaces it.
  defp cached(key) do
    case :persistent_term.get({__MODULE__, :cache}, nil) do
      {^key, value} -> value
      _ -> nil
    end
  end

  defp store(key, value) do
    :persistent_term.put({__MODULE__, :cache}, {key, value})
    value
  end

  defp repo_url, do: Workflow.Team.Source.team().repo_url

  defp ai? do
    Keyword.get(Application.get_env(:ex_tales_forge, __MODULE__, []), :ai, true) and
      String.downcase(String.trim(System.get_env("WHAT_WE_DID_AI", "true"))) != "false"
  end

  defp llm,
    do:
      Application.get_env(
        :ex_tales_forge,
        :what_we_did_llm,
        &TalesForge.PrFeed.WhatWeDidLLM.complete/3
      )
end
