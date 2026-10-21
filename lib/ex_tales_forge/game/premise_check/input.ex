defmodule TalesForge.Game.PremiseCheck.Input do
  @moduledoc """
  What `TalesForge.Game.PremiseCheck.state/1` builds the check state from:
  the session's `world_state` before and after this turn's rules
  (`world_before`, `world_after`), the session's `fronts` and the fights the
  character has won (`won_fights`: each won fight's player text and
  narration, or just their number).
  """

  alias TalesForge.Game.{Inventory, WorldClock}

  defstruct world_before: nil, world_after: nil, fronts: [], won_fights: 0

  @type t :: %__MODULE__{
          world_before: map() | nil,
          world_after: map() | nil,
          fronts: [map()],
          won_fights: non_neg_integer() | [String.t()]
        }

  @doc """
  The state to check claims against (`TalesForge.Game.PremiseCheck.state/1`).
  Items carried before or after the turn both count, and the larger purse
  counts, so an item bought or a coin spent this turn is never contradicted.
  """
  @spec state(t()) :: map()
  def state(%__MODULE__{won_fights: won_fights} = input) when is_list(won_fights) do
    %{input | won_fights: length(won_fights)}
    |> state()
    |> Map.put(:won_fights, won_fights)
  end

  def state(%__MODULE__{} = input) do
    before = character(input.world_before)
    after_turn = character(input.world_after)

    %{
      inventory: carried(before, after_turn),
      coins:
        Enum.max_by(
          [before["coins"] || %{}, after_turn["coins"] || %{}],
          &Inventory.coin_total_copper/1
        ),
      skills: after_turn["skills"] || before["skills"] || %{},
      people: [],
      fronts: Enum.map(input.fronts, &front/1),
      combat_wins: input.won_fights,
      clock: clock(input.world_before || input.world_after)
    }
  end

  # QA 2026-10-14 08:57: an item carried before and after the turn is listed
  # once.
  defp carried(before, after_turn) do
    (Inventory.normalize_items(before["inventory"] || []) ++
       Inventory.normalize_items(after_turn["inventory"] || []))
    |> Enum.uniq_by(&String.downcase(to_string(&1["name"] || &1["id"])))
  end

  defp clock(%{"world_tick" => tick}) when is_integer(tick) and tick >= 0,
    do: %{tick: tick, period: WorldClock.period(tick)}

  defp clock(_world), do: nil

  defp character(world) when is_map(world), do: Map.get(world, "character") || %{}
  defp character(_world), do: %{}

  defp front(front) do
    definition = Map.get(front, :definition) || %{}
    %{id: Map.get(front, :front_id), name: definition["name"], status: Map.get(front, :status)}
  end
end
