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

  The check finds the person from the action target (a world id or a
  name). When the target names nobody, the check reads the player's text
  for the name of a dead person (QA 2026-10-15 retest, session 9a1ff8c2:
  "I persuade Marta" at her body had no target, because the intent step
  sees only the living, and the turn rolled persuasion). The social skill
  comes from the action or from the verb in the text, so the intent
  classifier and the fallback reading get the same result.
  """

  alias TalesForge.Game.Mechanics
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
  @spec reason(map(), SingleAction.t(), String.t() | nil) :: String.t() | nil
  def reason(world, action, text \\ nil)

  def reason(world, %SingleAction{} = action, text) when is_map(world) do
    state = npc_state(world)
    skill = social_skill(action, text)

    case find_target(state, action.target, text) do
      nil -> nil
      target -> target_reason(world, action, skill, target, state[target])
    end
  end

  def reason(_world, _action, _text), do: nil

  defp target_reason(world, action, skill, target, npc) do
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

  defp npc_state(world) do
    case world["npc_state"] do
      %{} = state -> state
      _ -> %{}
    end
  end

  defp social_skill(action, text) do
    skill = (action.parameters || %{})["skill"] |> Mechanics.normalize_skill_name()

    cond do
      skill in @social_skills ->
        skill

      is_binary(text) and Mechanics.infer_check_skill(text) in @social_skills ->
        Mechanics.infer_check_skill(text)

      true ->
        skill
    end
  end

  # The world id of the target: the action target as an id or a name, else
  # a dead person that the text names.
  defp find_target(state, target, text) do
    named = if is_binary(target), do: by_name(state, target, fn _ -> true end)

    cond do
      is_binary(target) and Map.has_key?(state, target) -> target
      is_binary(named) -> named
      is_binary(text) -> by_name(state, text, &dead?/1)
      true -> nil
    end
  end

  defp dead?(npc), do: is_map(npc) and npc["vitality"] == "dead"

  # The id of the first person (by id) whose full name or a name word of
  # four letters or more is a word of `text`.
  defp by_name(state, text, keep?) do
    words = words(text)

    state
    |> Enum.filter(fn {_id, npc} -> is_map(npc) and keep?.(npc) end)
    |> Enum.sort_by(&elem(&1, 0))
    |> Enum.find_value(fn {id, npc} ->
      names = words("#{npc["name"]} #{String.replace(id, "_", " ")}")
      if Enum.any?(names, &(String.length(&1) >= 4 and &1 in words)), do: id
    end)
  end

  defp words(text) do
    text |> String.downcase() |> String.split(~r/[^\p{L}\p{N}]+/u, trim: true)
  end

  defp name(npc, id), do: npc["name"] || id

  defp place(world, npc) do
    id = npc["location_id"]
    if is_binary(id), do: World.runtime_location(world, id)["name"] || id, else: "another place"
  end
end
