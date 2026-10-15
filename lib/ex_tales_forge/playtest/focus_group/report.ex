defmodule TalesForge.Playtest.FocusGroup.Report do
  @moduledoc """
  Writes the focus-group report as Markdown and the short digest for the idea
  board card (call type: function).
  """

  alias TalesForge.Playtest.FocusGroup

  @doc "The default report path: `docs/research/focus-group-<date>.md`."
  @spec default_path(Date.t()) :: String.t()
  def default_path(date \\ Date.utc_today()),
    do: Path.join(["docs", "research", "focus-group-#{Date.to_iso8601(date)}.md"])

  @doc "The full Markdown report."
  @spec markdown([FocusGroup.interview()], [{String.t(), term()}], keyword()) :: String.t()
  def markdown(interviews, failures, opts \\ []) do
    date = Keyword.get(opts, :date, Date.utc_today())
    model = Keyword.get(opts, :model, "unknown")

    [
      "# Persona focus group, #{Date.to_iso8601(date)}\n",
      "Made by `mix focus_group.run` (model `#{model}`). The answers are synthetic: the playtest personas speak in character. Read them as structured brainstorming next to real playtest and forum evidence. Ronny is the red team.\n",
      "## Themes\n",
      themes_section(FocusGroup.themes(interviews)),
      "## Quit risks\n",
      quit_section(interviews),
      Enum.map(interviews, &persona_section/1),
      failures_section(failures)
    ]
    |> IO.iodata_to_binary()
  end

  defp themes_section([]), do: "No improvements came back.\n\n"

  defp themes_section(themes) do
    Enum.map(themes, fn {gap, items} ->
      [
        "### #{gap.title} (#{length(items)})\n\n",
        Enum.map(items, fn {name, imp} -> "- **#{name}:** #{imp}\n" end),
        "\n"
      ]
    end)
  end

  defp quit_section(interviews) do
    lines = for i <- interviews, risk <- i.quit_risks, do: "- **#{label(i)}:** #{risk}\n"
    if lines == [], do: "None came back.\n\n", else: [lines, "\n"]
  end

  defp persona_section(i) do
    by_id = Map.new(i.questions, &{&1.id, &1.text})

    [
      "## #{label(i)}\n\n",
      "Brief: about #{i.brief_tokens} tokens.\n\n",
      Enum.map(i.answers, fn a -> "**#{by_id[a.q_id]}**\n\n#{a.text}\n\n" end)
    ]
  end

  defp failures_section([]), do: []

  defp failures_section(failures) do
    [
      "## Interviews without a reply\n\n",
      Enum.map(failures, fn {id, reason} -> "- #{id}: `#{inspect(reason, limit: 5)}`\n" end)
    ]
  end

  defp label(%{persona: p, red_team: true}), do: "#{p.name} (red team)"
  defp label(%{persona: p}), do: p.name

  @doc "The short digest for the board card: counts, the top three themes, the report path."
  @spec digest([FocusGroup.interview()], [{String.t(), term()}], String.t()) :: String.t()
  def digest(interviews, failures, path) do
    top =
      interviews
      |> FocusGroup.themes()
      |> Enum.reject(fn {gap, _} -> gap.id == "other" end)
      |> Enum.take(3)
      |> Enum.map_join("; ", fn {gap, items} -> "#{gap.title} (#{length(items)})" end)

    [
      "Focus group: #{length(interviews)} of #{length(interviews) + length(failures)} personas answered.",
      top != "" && "Top themes: #{top}.",
      "Report: #{path}"
    ]
    |> Enum.filter(&is_binary/1)
    |> Enum.join(" ")
  end
end
