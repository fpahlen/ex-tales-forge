defmodule TalesForge.CharacterCreation.Checks do
  @moduledoc """
  The checks a draft must pass before play, as pure functions of a
  `TalesForge.CharacterCreation.Context`. Each returns an error or `false`.
  """
  alias TalesForge.CharacterCreation.{Context, Options}

  @doc "Every error for the draft in `ctx`, in a fixed order (empty when it passes)."
  @spec errors(Context.t()) :: [Context.error()]
  def errors(%Context{} = ctx) do
    [name(ctx), budget(ctx), rolled(ctx), race_picks(ctx), approval(ctx)]
    |> Kernel.++(stat_ranges(ctx))
    |> Kernel.++(ctx.skill_errors)
    |> Enum.filter(& &1)
  end

  defp name(%Context{draft: draft}), do: draft.name == "" && {:name, "type a name"}

  defp budget(%Context{draft: draft, points_spent: spent} = ctx) do
    {budget, _lo, _hi} = Context.point_buy(ctx)

    (draft.model in ["point_buy", "from_text"] and spent > budget) &&
      {:stats, "#{budget} points at most; #{spent} spent"}
  end

  defp rolled(%Context{draft: draft}) do
    (draft.model == "stat_roll" and draft.base_stats != draft.rolled_stats) &&
      {:stats, "the stats must be the rolled stats"}
  end

  defp race_picks(%Context{draft: draft, rules: rules}) do
    case Options.race_choice(rules["creation"], draft.race) do
      %{"count" => count} when length(draft.race_picks) != count ->
        {:race_picks, "choose #{count} stats for the #{draft.race} bonus"}

      _ ->
        false
    end
  end

  defp approval(%Context{draft: draft}) do
    (draft.model == "from_text" and not draft.approved) &&
      {:approval, "approve the AI draft before play"}
  end

  defp stat_ranges(%Context{draft: draft, modifiers: modifiers} = ctx) do
    {_budget, lo, hi} = Context.point_buy(ctx)

    for {stat, value} <- ctx.final_stats do
      (value < lo or value > hi) &&
        {:stats,
         "#{stat} would be #{value} after the #{draft.race} modifier " <>
           "(#{signed(Map.get(modifiers, stat, 0))}); it must be #{lo}–#{hi}"}
    end
  end

  defp signed(n) when n >= 0, do: "+#{n}"
  defp signed(n), do: "#{n}"
end
