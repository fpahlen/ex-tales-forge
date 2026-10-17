defmodule Mix.Tasks.Health.Check.Params do
  @moduledoc """
  The functions of `lib/` with #{4} or more parameters, read from the AST
  of each file: every `def` and `defp` head, one entry per name and arity.
  `@impl` callbacks are skipped (their arity is the behaviour's). Three is
  fine: Phoenix and OTP callbacks take three (`handle_event/3`,
  `handle_call/3`).
  """

  @min 4

  @doc "The lowest parameter count that is listed."
  @spec min() :: pos_integer()
  def min, do: @min

  @doc "Each function of the `.ex` files under `dir` with #{@min}+ parameters, sorted."
  @spec collect(Path.t()) :: [map()]
  def collect(dir \\ "lib") do
    "#{dir}/**/*.ex"
    |> Path.wildcard()
    |> Enum.flat_map(fn file -> file |> File.read!() |> wide(file) end)
    |> Enum.sort_by(& &1["function"])
  end

  @doc """
  The functions in `source` with #{@min}+ parameters.

      iex> source = \"""
      ...> defmodule A do
      ...>   def f(a, b, c, d), do: {a, b, c, d}
      ...>   defp g(a, b, c), do: {a, b, c}
      ...>   @impl true
      ...>   def handle(a, b, c, d), do: {a, b, c, d}
      ...>   def h(a, b, c, d \\\\\\\\ 1, e) when a > 0, do: {a, b, c, d, e}
      ...> end
      ...> \"""
      iex> Mix.Tasks.Health.Check.Params.wide(source, "lib/a.ex")
      [%{"function" => "A.f/4", "file" => "lib/a.ex", "params" => 4},
       %{"function" => "A.h/5", "file" => "lib/a.ex", "params" => 5}]
  """
  @spec wide(String.t(), Path.t()) :: [map()]
  def wide(source, file) do
    source
    |> Code.string_to_quoted!()
    |> modules(nil)
    |> Enum.flat_map(fn {mod, body} -> heads(mod, body) end)
    |> Enum.uniq()
    |> Enum.filter(fn {_mod, _name, n} -> n >= @min end)
    |> Enum.map(fn {mod, name, n} ->
      %{"function" => "#{mod}.#{name}/#{n}", "file" => file, "params" => n}
    end)
  end

  # Every module in the AST with the statements of its body, nested
  # modules with their full name.
  defp modules({:defmodule, _, [{:__aliases__, _, parts}, [do: body]]}, parent) do
    name = Enum.join([parent | parts] |> Enum.reject(&is_nil/1), ".")
    stmts = statements(body)
    [{name, stmts} | Enum.flat_map(stmts, &modules(&1, name))]
  end

  defp modules({:__block__, _, stmts}, parent), do: Enum.flat_map(stmts, &modules(&1, parent))
  defp modules(_ast, _parent), do: []

  defp statements({:__block__, _, stmts}), do: stmts
  defp statements(stmt), do: [stmt]

  # {module, name, params} of each def/defp head that is not an @impl
  # callback. An @impl marks the next head's name and arity.
  defp heads(mod, stmts) do
    {heads, _impl, _next} =
      Enum.reduce(stmts, {[], MapSet.new(), false}, fn
        {:@, _, [{:impl, _, _}]}, {acc, impl, _} ->
          {acc, impl, true}

        {kind, _, [head | _]}, state when kind in [:def, :defp] ->
          head(mod, head, state)

        _stmt, state ->
          state
      end)

    Enum.reverse(heads)
  end

  defp head(mod, {:when, _, [call | _]}, state), do: head(mod, call, state)

  defp head(mod, {name, _, args}, {acc, impl, next}) when is_atom(name) do
    key = {name, length(List.wrap(args))}

    if next or key in impl,
      do: {acc, MapSet.put(impl, key), false},
      else: {[{mod, name, elem(key, 1)} | acc], impl, false}
  end

  defp head(_mod, _head, {acc, impl, _next}), do: {acc, impl, false}
end
