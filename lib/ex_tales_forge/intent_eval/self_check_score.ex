defmodule TalesForge.IntentEval.SelfCheckScore do
  @moduledoc """
  Scores a reader's self-check read (`TalesForge.Game.SelfCheck`: is the player
  asking about their own coins or pack?) against `gold["self_check"]`
  (`none`, `coins`, `pack` or `both`).

  Only readings that carry `:self_check` count; a reader without one scores
  nothing. Accuracy is over the labelled items. A misfire is a read on an item
  whose gold is `none` or that has no self-check label; a miss is a labelled
  self-check read as nothing. The fallback is tuned to miss rather than
  misfire.
  """

  alias TalesForge.Game.SelfCheck

  @doc "The self-check numbers over `{item, reading}` pairs."
  @spec evaluate([{map(), map()}]) :: map()
  def evaluate(pairs) do
    read = Enum.filter(pairs, fn {_item, r} -> is_list(Map.get(r, :self_check)) end)
    labelled = Enum.filter(read, fn {item, _r} -> is_binary(gold(item)) end)

    %{
      read: length(read),
      accuracy: accuracy(labelled),
      misses: Enum.count(labelled, &miss?/1),
      misfires: Enum.count(read, &misfire?/1)
    }
  end

  defp miss?({item, r}), do: gold(item) != "none" and r.self_check == []
  defp misfire?({item, r}), do: gold(item) in [nil, "none"] and r.self_check != []

  @doc "The report section, or `\"\"` when the reader read no self-checks."
  @spec section(map()) :: String.t()
  def section(%{read: 0}), do: ""

  def section(%{accuracy: a} = s) do
    "### Self-check (coins / pack)\n\n" <>
      "Labelled: #{a.correct}/#{a.n} right; #{s.misses} missed; " <>
      "#{s.misfires} misfires over #{s.read} items read."
  end

  defp accuracy(labelled) do
    correct =
      Enum.count(labelled, fn {item, r} -> SelfCheck.label(r.self_check) == gold(item) end)

    %{n: length(labelled), correct: correct}
  end

  defp gold(item), do: get_in(item, ["gold", "self_check"])
end
