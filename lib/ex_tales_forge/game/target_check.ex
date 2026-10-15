defmodule TalesForge.Game.TargetCheck do
  @moduledoc """
  Blocks an action at a person who cannot take it (QA 2026-10-15, Gentry,
  session 99817343):

    * a dead person cannot be talked to, fought, persuaded, traded with or
      trained by. Before, a dead Marta talked and got a persuasion roll;
    * a persuasion, deception or intimidation at a person who is elsewhere
      has nobody to roll against. Before, the game moved the character to
      Henrik with no roll; now the player is told where the person is.

  A blocked action rolls nothing and costs no game time
  (`TalesForge.Game.Turn.Mechanics`).
  """

  alias TalesForge.Game.Schemas.SingleAction
  alias TalesForge.Game.World

  @person_actions ~w(speak combat give trade buy sell train spend)a
  @social_skills ~w(persuasion deception intimidation)

  @doc "The social skills, which need the person present."
  @spec social_skills() :: [String.t()]
  def social_skills, do: @social_skills

  @doc """
  The reason the action is blocked, or nil.

      iex> world = %{"present_npcs" => ["marta_kellen"], "npc_state" => %{"marta_kellen" =>
      ...>   %{"name" => "Marta Kellen", "vitality" => "dead", "location_id" => "weary_pilgrim"}}}
      iex> action = %TalesForge.Game.Schemas.SingleAction{action_type: :speak, target: "marta_kellen"}
      iex> TalesForge.Game.TargetCheck.reason(world, action)
      "Marta Kellen is dead. The dead do not talk, fight, trade or listen."
      iex> TalesForge.Game.TargetCheck.reason(world, %{action | action_type: :observe})
      nil
  """
  @spec reason(map(), SingleAction.t()) :: String.t() | nil
  def reason(world, %SingleAction{target: target} = action) when is_binary(target) do
    npc = get_in(world, ["npc_state", target])
    skill = (action.parameters || %{})["skill"]

    cond do
      not is_map(npc) ->
        nil

      npc["vitality"] == "dead" and
          (action.action_type in @person_actions or skill in @social_skills) ->
        "#{name(npc, target)} is dead. The dead do not talk, fight, trade or listen."

      skill in @social_skills and target not in List.wrap(world["present_npcs"]) ->
        "#{name(npc, target)} is not here. #{name(npc, target)} is at #{place(world, npc)}. " <>
          "Go there first."

      true ->
        nil
    end
  end

  def reason(_world, _action), do: nil

  defp name(npc, id), do: npc["name"] || id

  defp place(world, npc) do
    id = npc["location_id"]
    if is_binary(id), do: World.runtime_location(world, id)["name"] || id, else: "another place"
  end
end
