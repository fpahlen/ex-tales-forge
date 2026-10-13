defmodule Workflow.NameCheck do
  @moduledoc """
  Finds team names in Workflow source files. Pure: the caller reads the files
  (`mix workflow.check_names`).

  The names come from the team config (`Workflow.Team`):

    * the product name (`"Example Product"`) and its kebab form
      (`"example-product"`), the repo URL, its `owner/name` and the docs repo
    * each founder name and GitHub login
    * each bot name

  A founder handle or a bot id can also be a common word (for example an
  Elixir keyword). The check finds a bot id only in a code form: `:id`,
  `"id"`, `` `@id ``, `bot:id` or a word in a `~w(...)` list. It finds a
  founder handle only as `` `@handle `` or in a `~w(...)` list. A bare `@id`
  is also a module attribute, and a quoted word can be a JSON key, so the
  check does not read these forms for a founder handle.

  Module names and the app name are shared wiring (`TalesForge`,
  `:ex_tales_forge`). The check does not read them, because the kebab form
  needs a hyphen and the name needs a space.
  """

  alias Workflow.Team

  @typedoc "A finding: the file, the line number, the name and the line."
  @type finding :: %{path: String.t(), line: pos_integer(), name: String.t(), text: String.t()}

  @doc """
  The findings in `files` (`{path, content}` pairs) for `team`.

      iex> team = Workflow.Team.example()
      iex> files = [{"a.ex", "# Rita reads it.\\ncase x do\\n"}, {"b.ex", "x = ~w(rita lin)"}]
      iex> Workflow.NameCheck.findings(team, files) |> Enum.map(&{&1.path, &1.line, &1.name})
      [{"a.ex", 1, "Rita"}, {"b.ex", 1, "lin"}, {"b.ex", 1, "rita"}]
      iex> Workflow.NameCheck.findings(team, [{"c.ex", "defmodule ExampleProduct.Board do"}])
      []
  """
  @spec findings(Team.t(), [{String.t(), String.t()}]) :: [finding()]
  def findings(%Team{} = team, files) do
    patterns = patterns(team)

    for {path, content} <- files,
        {text, n} <- content |> String.split("\n") |> Enum.with_index(1),
        {name, regex} <- patterns,
        Regex.match?(regex, text),
        uniq: true do
      %{path: path, line: n, name: name, text: String.trim(text)}
    end
    |> Enum.sort_by(&{&1.path, &1.line, &1.name})
  end

  @doc """
  The names that the check looks for, with their regexes.

      iex> Workflow.Team.example() |> Workflow.NameCheck.patterns() |> Enum.map(&elem(&1, 0)) |> Enum.take(3)
      ["Example Product", "example-product", "https://example.com/org/product"]
  """
  @spec patterns(Team.t()) :: [{String.t(), Regex.t()}]
  def patterns(%Team{} = team) do
    repo = team.repo_url |> URI.parse() |> Map.get(:path, "") |> to_string() |> String.trim("/")

    words =
      [team.product_name, kebab(team.product_name), team.repo_url, repo, team.docs_repo] ++
        Enum.map(team.founders, & &1.name) ++
        for(%{github: gh} <- team.founders, is_binary(gh), do: gh) ++
        Enum.map(team.bots, & &1.name)

    founder_tokens = Team.handles(team) -- Team.bot_handles(team)

    word_patterns =
      for w <- Enum.uniq(words), w != "" do
        {w, Regex.compile!("(?<![\\p{L}\\d_-])" <> Regex.escape(w) <> "(?![\\p{L}\\d_])", "u")}
      end

    token_patterns =
      for(t <- Team.bot_handles(team), t != "", do: {t, token_regex(t, true)}) ++
        for t <- Enum.uniq(founder_tokens), t != "", do: {t, token_regex(t, false)}

    word_patterns ++ token_patterns
  end

  # A bot id in a code form. A founder handle only as a `@handle` in a doc or
  # in a ~w list: a quoted handle can also be a JSON key (for example "max").
  defp token_regex(t, quoted?) do
    e = Regex.escape(t)
    bot = if quoted?, do: "(?<![\\w])(:|bot:)#{e}(?![\\w])|\"#{e}\"|", else: ""
    Regex.compile!(bot <> "`@#{e}(?![\\w])|~w[(\\[][^)\\]]*(?<![\\w])#{e}(?![\\w])", "iu")
  end

  defp kebab(name), do: name |> String.downcase() |> String.replace(~r/\s+/, "-")
end
