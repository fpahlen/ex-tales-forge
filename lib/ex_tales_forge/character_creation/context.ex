defmodule TalesForge.CharacterCreation.Context do
  @moduledoc """
  A draft with what the checks and the finished sheet need from its
  adventure's rules, worked out once: the rules, the points spent, the race
  modifiers, the final stats and the skill errors.
  """
  alias TalesForge.CharacterCreation.Draft

  @enforce_keys [:draft]
  defstruct draft: nil,
            rules: %{},
            points_spent: 0,
            modifiers: %{},
            final_stats: %{},
            skill_errors: []

  @type error :: {atom(), String.t()}

  @type t :: %__MODULE__{
          draft: Draft.t(),
          rules: %{required(String.t()) => map()},
          points_spent: integer(),
          modifiers: %{optional(String.t()) => integer()},
          final_stats: %{optional(String.t()) => integer()},
          skill_errors: [error() | false]
        }

  @doc "The point-buy limits: `{budget, min, max}`."
  @spec point_buy(t()) :: {integer(), integer(), integer()}
  def point_buy(%__MODULE__{rules: rules}) do
    %{"budget" => budget, "min" => lo, "max" => hi} = rules["creation"]["point_buy"]
    {budget, lo, hi}
  end
end
