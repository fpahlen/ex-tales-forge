defmodule TalesForge.NPCSignals.Turn do
  @moduledoc """
  A finished turn as `TalesForge.NPCSignals.intentions/1` sees it:
  the session, the world after the turn, the action handler, the player's
  words and, when known, the world before the turn (for the tick delta).
  """

  @enforce_keys [:session_id, :world_state, :handler, :raw_action]
  defstruct [:session_id, :world_state, :handler, :raw_action, world_before: nil]

  @type t :: %__MODULE__{
          session_id: String.t(),
          world_state: map(),
          handler: map(),
          raw_action: String.t() | nil,
          world_before: map() | nil
        }

  alias TalesForge.Game.ActionHandler

  @doc "The world tick after the turn."
  @spec world_tick(t()) :: integer()
  def world_tick(%__MODULE__{world_state: world_state}), do: Map.get(world_state, "world_tick", 0)

  @doc """
  The ticks that passed: the world tick after the turn less `world_before`'s,
  or the handler's tick delta when `world_before` has no tick.
  """
  @spec tick_delta(t()) :: integer()
  def tick_delta(%__MODULE__{world_before: %{"world_tick" => before}} = turn)
      when is_integer(before),
      do: world_tick(turn) - before

  def tick_delta(%__MODULE__{handler: handler}), do: ActionHandler.tick_delta(handler)
end
