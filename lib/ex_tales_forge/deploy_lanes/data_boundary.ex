defmodule TalesForge.DeployLanes.DataBoundary do
  @moduledoc """
  The data boundary between Workflow and the product app
  (`priv/team/data-boundary.txt`, `TalesForge.Workflow.Repo`).

  Workflow data is a schema module with the prefix `workflow`,
  `TalesForge.Workflow.Repo` and `TalesForge.Workflow.Jobs`. Product-app data
  is every other schema module and `TalesForge.Repo`.

  Two rules apply to the file-level dependencies under `lib/`:

  1. Product-app code does not depend on Workflow data.
  2. Workflow code does not depend on product-app data.

  A `[wiring]` file (the application and the release tasks) starts both
  repos, so the rules skip it. A `[pending]` file may still depend on
  product-app data until a later card moves it to the product-app API.
  `mix deploy.check_boundaries` runs this check.
  """

  @typedoc "The sections of the data boundary file, as glob lists."
  @type t :: %{workflow: [String.t()], wiring: [String.t()], pending: [String.t()]}

  @typedoc "The concrete file sets that the check uses."
  @type sets :: %{
          workflow: MapSet.t(String.t()),
          wiring: MapSet.t(String.t()),
          pending: MapSet.t(String.t()),
          workflow_data: MapSet.t(String.t()),
          product_data: MapSet.t(String.t())
        }

  @typedoc "One dependency that breaks the data boundary."
  @type violation :: %{
          kind: :product_to_workflow | :workflow_to_product,
          from: String.t(),
          to: String.t()
        }

  @default_path "priv/team/data-boundary.txt"

  @doc "The path of the data boundary file."
  @spec default_path() :: String.t()
  def default_path, do: @default_path

  @doc """
  Parses the data boundary file. Each line under a `[section]` is one glob.
  `#` starts a comment.

      iex> TalesForge.DeployLanes.DataBoundary.parse("[workflow]\\nlib/a.ex # x\\n[pending]\\nlib/b.ex\\n")
      %{workflow: ["lib/a.ex"], wiring: [], pending: ["lib/b.ex"]}
  """
  @spec parse(String.t()) :: t()
  def parse(text) do
    text
    |> String.split("\n")
    |> Enum.map(&(&1 |> String.split("#", parts: 2) |> hd() |> String.trim()))
    |> Enum.reject(&(&1 == ""))
    |> Enum.reduce({nil, %{workflow: [], wiring: [], pending: []}}, &parse_line/2)
    |> elem(1)
    |> Map.new(fn {k, v} -> {k, Enum.reverse(v)} end)
  end

  defp parse_line("[workflow]", {_, acc}), do: {:workflow, acc}
  defp parse_line("[wiring]", {_, acc}), do: {:wiring, acc}
  defp parse_line("[pending]", {_, acc}), do: {:pending, acc}
  defp parse_line("[" <> _ = line, _), do: raise(ArgumentError, "unknown section #{line}")
  defp parse_line(_line, {nil, _}), do: raise(ArgumentError, "a pattern before a section")
  defp parse_line(line, {key, acc}), do: {key, Map.update!(acc, key, &[line | &1])}

  @doc """
  The dependencies that break the data boundary, sorted. Only `lib/` files
  count. A file in `workflow` is Workflow code. Every other file is
  product-app code.

      iex> sets = %{
      ...>   workflow: MapSet.new(["lib/board.ex", "lib/wf_repo.ex"]),
      ...>   wiring: MapSet.new(["lib/application.ex"]),
      ...>   pending: MapSet.new([]),
      ...>   workflow_data: MapSet.new(["lib/wf_repo.ex"]),
      ...>   product_data: MapSet.new(["lib/repo.ex"])
      ...> }
      iex> TalesForge.DeployLanes.DataBoundary.violations(sets, [
      ...>   {"lib/board.ex", "lib/wf_repo.ex"},
      ...>   {"lib/board.ex", "lib/repo.ex"},
      ...>   {"lib/game.ex", "lib/wf_repo.ex"},
      ...>   {"lib/application.ex", "lib/wf_repo.ex"}
      ...> ])
      [
        %{kind: :product_to_workflow, from: "lib/game.ex", to: "lib/wf_repo.ex"},
        %{kind: :workflow_to_product, from: "lib/board.ex", to: "lib/repo.ex"}
      ]
  """
  @spec violations(sets(), [{String.t(), String.t()}]) :: [violation()]
  def violations(sets, edges) do
    edges
    |> Enum.filter(fn {from, _} ->
      String.starts_with?(from, "lib/") and not MapSet.member?(sets.wiring, from)
    end)
    |> Enum.flat_map(&check(sets, &1))
    |> Enum.uniq()
    |> Enum.sort_by(&{&1.kind, &1.from, &1.to})
  end

  defp check(sets, {from, to}) do
    workflow? = MapSet.member?(sets.workflow, from)

    cond do
      not workflow? and MapSet.member?(sets.workflow_data, to) ->
        [%{kind: :product_to_workflow, from: from, to: to}]

      workflow? and MapSet.member?(sets.product_data, to) and
          not MapSet.member?(sets.pending, from) ->
        [%{kind: :workflow_to_product, from: from, to: to}]

      true ->
        []
    end
  end

  @doc """
  Splits schema files into Workflow data and product-app data. Each entry
  is `{file, prefix}`. A schema with the prefix `workflow` is Workflow data.
  """
  @spec split_schemas([{String.t(), String.t() | nil}]) ::
          {MapSet.t(String.t()), MapSet.t(String.t())}
  def split_schemas(schemas) do
    {workflow, product} = Enum.split_with(schemas, fn {_file, prefix} -> prefix == "workflow" end)
    {MapSet.new(workflow, &elem(&1, 0)), MapSet.new(product, &elem(&1, 0))}
  end
end
