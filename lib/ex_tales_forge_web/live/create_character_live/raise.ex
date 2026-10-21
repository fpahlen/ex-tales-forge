defmodule TalesForgeWeb.CreateCharacterLive.Raise do
  @moduledoc """
  One skill's raise button on the creation screen: the skill's `level`, the
  skill points `left`, the number of `signatures` and the skill `rules`.
  """

  defstruct level: 0, left: 0, signatures: 0, rules: %{}

  @type t :: %__MODULE__{
          level: non_neg_integer(),
          left: integer(),
          signatures: non_neg_integer(),
          rules: map()
        }

  @doc """
  One more level is affordable, under the signature cap, and a new signature
  skill only while there is room for one.
  """
  @spec allowed?(t()) :: boolean()
  def allowed?(%__MODULE__{level: level, left: left, signatures: signatures, rules: rules}) do
    costs = rules["level_costs"]
    price = Enum.at(costs, level, List.last(costs))

    level < rules["signature_cap"] and price <= left and
      (level != rules["cap"] or signatures < rules["signature_max"])
  end
end
