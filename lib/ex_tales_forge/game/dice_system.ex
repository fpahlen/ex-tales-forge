defmodule TalesForge.Game.DiceSystem do
  @moduledoc """
  The dice system of a game. It is a setting for each game type.

  Today there is one system: `"skill_d100"`, a percentage roll-under system.
  Skills go from 1 to 100 and a roll succeeds when 1d100 is equal to or less
  than the effective skill (`TalesForge.Game.Mechanics.resolve_check/2`).

  A session's `world_state["game_system"]` names its system. A session with
  no value uses the default. This module is the hook for more systems later:
  add the name to `@systems` and branch on `for_world/1` where the rules
  differ.

      iex> TalesForge.Game.DiceSystem.default()
      "skill_d100"
      iex> TalesForge.Game.DiceSystem.for_world(%{})
      "skill_d100"
      iex> TalesForge.Game.DiceSystem.for_world(%{"game_system" => "skill_d100"})
      "skill_d100"
  """

  @default "skill_d100"
  @systems [@default]

  @doc "The default dice system."
  @spec default() :: String.t()
  def default, do: @default

  @doc "The known dice systems."
  @spec systems() :: [String.t()]
  def systems, do: @systems

  @doc "The dice system of a world state: its `game_system`, or the default."
  @spec for_world(map() | nil) :: String.t()
  def for_world(%{"game_system" => system}) when is_binary(system) and system != "", do: system
  def for_world(_world), do: @default

  @doc "The sides of the die for `system`."
  @spec die(String.t()) :: pos_integer()
  def die("skill_d100"), do: 100
end
