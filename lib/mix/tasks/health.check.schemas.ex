defmodule Mix.Tasks.Health.Check.Schemas do
  @moduledoc """
  Ecto association edges: a file with `use Ecto.Schema` whose only
  references to another file are association targets (`belongs_to`,
  `has_many`, `has_one`, `many_to_many`). A parent's `has_many` and its
  child's `belongs_to` make a 2-cycle in xref; that pair is the framework
  idiom, not a tangle, so the cycles leave such edges out (like the `~p`
  edges to the router, see `Mix.Tasks.Health.Check`).

  An edge stays when the schema file also names the other file's module
  anywhere else (a struct, a call, an `import`): that is real coupling.
  Module names are read from the AST, so docs and strings do not count.
  """

  @associations [:belongs_to, :has_many, :has_one, :many_to_many]

  @doc "The `{from, to}` file edges that are association targets only."
  @spec edges(Path.t()) :: MapSet.t({String.t(), String.t()})
  def edges(dir \\ "lib") do
    sources = Map.new(Path.wildcard("#{dir}/**/*.ex"), &{&1, quoted(&1)})
    owner = for {file, ast} <- sources, mod <- modules(ast), into: %{}, do: {mod, file}

    for {file, ast} <- sources,
        schema?(ast),
        to <- association_files(ast, owner, file),
        into: MapSet.new(),
        do: {file, to}
  end

  defp quoted(file), do: file |> File.read!() |> Code.string_to_quoted!()

  defp association_files(ast, owner, file) do
    for {to, true} <- by_file(references(ast), owner), to != file, do: to
  end

  @doc """
  Whether a cycle (its files in xref's order, each one referencing the
  next and the last the first) has an association edge, so it does not
  count.

      iex> edges = MapSet.new([{"lib/vote.ex", "lib/idea.ex"}])
      iex> Mix.Tasks.Health.Check.Schemas.exempt?(["lib/idea.ex", "lib/vote.ex"], edges)
      true
      iex> Mix.Tasks.Health.Check.Schemas.exempt?(["lib/vote.ex", "lib/board.ex"], edges)
      false
  """
  @spec exempt?([String.t()], MapSet.t()) :: boolean()
  def exempt?(files, edges) do
    files
    |> Enum.zip(tl(files) ++ [hd(files)])
    |> Enum.any?(&MapSet.member?(edges, &1))
  end

  @doc """
  The modules a file references, each with whether every reference is an
  association target (an `alias` line does not count either way).

      iex> ast = Code.string_to_quoted!(\"""
      ...> defmodule A.Vote do
      ...>   use Ecto.Schema
      ...>   alias A.Idea
      ...>   schema "votes" do
      ...>     belongs_to :idea, Idea
      ...>   end
      ...>   def new, do: %A.Board{}
      ...> end
      ...> \""")
      iex> Mix.Tasks.Health.Check.Schemas.references(ast)
      %{A.Board => false, A.Idea => true, Ecto.Schema => false}
  """
  @spec references(Macro.t()) :: %{module() => boolean()}
  def references(ast) do
    aliases = aliases(ast)

    {_, refs} =
      Macro.prewalk(ast, %{}, fn
        {:alias, _, _}, acc ->
          {nil, acc}

        {:defmodule, _, [_name, body]}, acc ->
          {body, acc}

        {assoc, _, [_name, target | opts]}, acc when assoc in @associations ->
          {opts, mark(acc, resolve(target, aliases), true)}

        {:__aliases__, _, _} = node, acc ->
          {node, mark(acc, resolve(node, aliases), false)}

        node, acc ->
          {node, acc}
      end)

    Map.delete(refs, nil)
  end

  defp mark(acc, nil, _), do: acc
  defp mark(acc, mod, assoc?), do: Map.update(acc, mod, assoc?, &(&1 and assoc?))

  defp by_file(refs, owner) do
    refs
    |> Enum.flat_map(fn {mod, assoc?} ->
      case owner do
        %{^mod => file} -> [{file, assoc?}]
        _ -> []
      end
    end)
    |> Enum.group_by(&elem(&1, 0), &elem(&1, 1))
    |> Enum.map(fn {file, flags} -> {file, Enum.all?(flags)} end)
  end

  defp schema?(ast) do
    {_, found} =
      Macro.prewalk(ast, false, fn
        {:use, _, [{:__aliases__, _, [:Ecto, :Schema]} | _]} = node, _ -> {node, true}
        node, found -> {node, found}
      end)

    found
  end

  # `alias A.B` and `alias A.B, as: C`, file-wide (enough for schemas).
  defp aliases(ast) do
    {_, acc} =
      Macro.prewalk(ast, %{}, fn
        {:alias, _, [{{:., _, [{:__aliases__, _, base}, :{}]}, _, names}]} = node, acc ->
          {node, Enum.reduce(names, acc, &multi_alias(&1, base, &2))}

        {:alias, _, [{:__aliases__, _, parts} | opts]} = node, acc ->
          as =
            case opts do
              [[as: {:__aliases__, _, [name]}]] -> name
              _ -> List.last(parts)
            end

          {node, Map.put(acc, as, Module.concat(parts))}

        node, acc ->
          {node, acc}
      end)

    acc
  end

  defp multi_alias({:__aliases__, _, parts}, base, acc),
    do: Map.put(acc, List.last(parts), Module.concat(base ++ parts))

  defp multi_alias(_, _, acc), do: acc

  defp resolve({:__aliases__, _, [head | rest]}, aliases) when is_atom(head) do
    case aliases do
      %{^head => mod} -> Module.concat([mod | rest])
      _ -> Module.concat([head | rest])
    end
  end

  defp resolve(_, _), do: nil

  defp modules(ast, prefix \\ nil) do
    {_, mods} =
      Macro.prewalk(ast, [], fn
        {:defmodule, _, [{:__aliases__, _, parts}, body]}, acc ->
          mod = if prefix, do: Module.concat([prefix | parts]), else: Module.concat(parts)
          {nil, [mod | modules(body, mod)] ++ acc}

        node, acc ->
          {node, acc}
      end)

    List.flatten(mods)
  end
end
