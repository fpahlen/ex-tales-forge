defmodule Mix.Tasks.Health.Check.LiveViews do
  @moduledoc """
  LiveView -> LiveView references: a LiveView file (one that has
  `use TalesForgeWeb, :live_view` or `:public_live_view`, read from the AST)
  that references another LiveView file in the xref graph. Pages that
  render or call each other tangle the web layer; the router does not
  count (see `Mix.Tasks.Health.Check`), so this keeps that tangle visible.
  """

  @kinds [:live_view, :public_live_view]

  @doc "The LiveView files among the `.ex` files under `dir`, sorted."
  @spec files(Path.t()) :: [String.t()]
  def files(dir \\ "lib") do
    "#{dir}/**/*.ex"
    |> Path.wildcard()
    |> Enum.filter(&(&1 |> File.read!() |> live_view?()))
    |> Enum.sort()
  end

  @doc """
  Whether `source` is a LiveView: a `use TalesForgeWeb, :live_view` (or
  `:public_live_view`) outside a `quote`.

      iex> Mix.Tasks.Health.Check.LiveViews.live_view?("defmodule A do\\n  use TalesForgeWeb, :live_view\\nend")
      true
      iex> Mix.Tasks.Health.Check.LiveViews.live_view?(~s|@moduledoc "use TalesForgeWeb, :live_view"|)
      false
  """
  @spec live_view?(String.t()) :: boolean()
  def live_view?(source) do
    source
    |> Code.string_to_quoted!()
    |> Macro.prewalk(false, fn
      {:quote, _, _}, found ->
        {nil, found}

      {:use, _, [{:__aliases__, _, [:TalesForgeWeb]}, kind]} = node, _ when kind in @kinds ->
        {node, true}

      node, found ->
        {node, found}
    end)
    |> elem(1)
  end

  @doc """
  The references between different files of `live_views` among the
  `{source, sink}` edges, as `%{"from" => file, "to" => [files]}`.

      iex> Mix.Tasks.Health.Check.LiveViews.references(["a", "b"], [{"a", "b"}, {"a", "c"}, {"b", "b"}])
      [%{"from" => "a", "to" => ["b"]}]
  """
  @spec references([String.t()], [{String.t(), String.t()}]) :: [map()]
  def references(live_views, edges) do
    live_views = MapSet.new(live_views)

    edges
    |> Enum.filter(&between?(&1, live_views))
    |> Enum.group_by(&elem(&1, 0), &elem(&1, 1))
    |> Enum.map(fn {from, to} -> %{"from" => from, "to" => to |> Enum.uniq() |> Enum.sort()} end)
    |> Enum.sort_by(& &1["from"])
  end

  defp between?({from, to}, live_views),
    do: from != to and MapSet.member?(live_views, from) and MapSet.member?(live_views, to)
end
