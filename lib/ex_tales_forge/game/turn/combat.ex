defmodule TalesForge.Game.Turn.Combat do
  @moduledoc """
  The opposed combat steps of stage 3 (`TalesForge.Game.Turn.Mechanics`),
  only with `COMBAT_OPPOSED=on`. The math is in `TalesForge.Game.Combat`.

    * `target/4` — before the roll: finds the person that the attack is aimed
      at. An unclear target blocks the action, and the turn asks the player.
    * `exchange/4` — after the roll: the player's d100 is the attack, and the
      defender may counterattack.
    * `book/4` — after the board: keeps the NPC wounds and minor foes in
      `world_state["npc_state"]`, writes the exchange to the outcome record
      and adds the `npc.down` or `npc.dead` event.

  NPC fighters and the character rules come from the `fighter` and
  `character_rules` adapters. The rolls come from `opts[:combat_rolls]` in
  tests, otherwise from `:rand`.
  """

  alias TalesForge.Characters.Defaults
  alias TalesForge.Game.Combat
  alias TalesForge.Game.Schemas.{HandlerResult, PlayerAction}
  alias TalesForge.Game.Turn

  @doc "True when opposed combat is on for `turn`."
  @spec on?(Turn.t()) :: boolean()
  def on?(turn), do: Turn.flag?(turn, :combat_opposed)

  @doc """
  The target of a combat roll. Returns `{played, handler, target}`. For an
  unclear target, the handler is a rejected `narrate` handler that asks the
  player, the played action has no skill, and the target is
  `{:unclear, names}`. Without a combat roll, the target is nil.
  """
  @spec target(Turn.t(), map(), PlayerAction.t(), HandlerResult.t()) ::
          {PlayerAction.t(), HandlerResult.t(), Combat.target() | nil}
  def target(turn, world, played, handler) do
    if on?(turn) and combat_roll?(handler) do
      case Combat.target(played.action.target, turn.raw_action, world) do
        {:unclear, names} -> {unrolled(played), ask(names), {:unclear, names}}
        found -> {played, handler, found}
      end
    else
      {played, handler, nil}
    end
  end

  defp combat_roll?(%{handler: "skill_check", skill: skill, state_hints: hints}),
    do: skill in Combat.combat_skills() and Map.get(hints || %{}, "rejected") != true

  defp combat_roll?(_handler), do: false

  defp unrolled(%PlayerAction{action: action} = played),
    do: %{played | action: %{action | parameters: Map.delete(action.parameters, "skill")}}

  defp ask(names) do
    people = if names == [], do: "nobody", else: Enum.join(names, ", ")

    %HandlerResult{
      handler: "narrate",
      notes: "Combat: the target is unclear. Ask the player whom the character attacks.",
      state_hints: %{
        "combat_target_unclear" => true,
        "rejected" => true,
        "reason" => "The target of the attack is unclear. The people here: #{people}."
      }
    }
  end

  @doc """
  The exchange for `target`, with the player's d100 from `mechanical`.
  Returns `{exchange, foe}`: `foe` is the minor foe fighter when the server
  made one. Returns `{%{"target_unclear" => names}, nil}` for an unclear
  target and `{nil, nil}` without a target or a roll.
  """
  @spec exchange(Turn.t(), map(), Combat.target() | nil, map()) :: {map() | nil, map() | nil}
  def exchange(_turn, _world, {:unclear, names}, _mechanical),
    do: {%{"target_unclear" => names}, nil}

  def exchange(_turn, _world, nil, _mechanical), do: {nil, nil}
  def exchange(_turn, _world, _target, %{roll: nil}), do: {nil, nil}

  def exchange(turn, world, target, mechanical) do
    {defender, foe} = defender(turn, world, target)
    character = Map.get(world, "character", %{})

    player =
      Map.merge(character, %{"id" => "player", "name" => character["name"] || "the character"})

    {Combat.exchange(player, defender, mechanical.skill, rolls(turn, mechanical)), foe}
  end

  defp defender(turn, world, {:npc, id}) do
    state = get_in(world, ["npc_state", id]) || %{}

    if state["minor"] == true do
      {state, nil}
    else
      case turn.adapters.fighter.(turn.session.id, id) do
        nil -> new_foe(turn, world, id, state["name"] || id)
        profile -> {Map.merge(profile, Map.take(state, ~w(wounds vitality))), nil}
      end
    end
  end

  defp defender(turn, world, {:foe, id, name}), do: new_foe(turn, world, id, name)

  defp new_foe(turn, world, id, name) do
    rules = turn.adapters.character_rules.(world["adventure_id"])
    foe = Combat.minor_foe(id, name, rules, Defaults.seed(turn.session.id, id))
    {foe, foe}
  end

  defp rolls(turn, mechanical) do
    injected = Keyword.get(turn.opts, :combat_rolls, %{})

    %{
      attack: Map.get(injected, :attack, mechanical.roll),
      counter_chance: Map.get_lazy(injected, :counter_chance, &:rand.uniform/0),
      counter: Map.get_lazy(injected, :counter, fn -> :rand.uniform(100) end),
      death: Map.get_lazy(injected, :death, fn -> :rand.uniform(100) end)
    }
  end

  @doc """
  Books the exchange on the board: carries the combat state of the world
  before the turn into the new npc_state, writes the defender's wounds,
  puts the exchange in the outcome record (`"combat"`) and adds the events.
  """
  @spec book(map(), map(), map() | nil, map() | nil) :: map()
  def book(board, world_before, exchange, foe) do
    before = Map.get(world_before, "npc_state") || %{}
    carried = Combat.carry(before, Map.get(board.world, "npc_state"))
    carried_world = Map.put(board.world, "npc_state", carried)

    {world, events} =
      case exchange do
        %{"attack" => _} ->
          {booked, events} = Combat.book(carried_world, exchange, foe, before)
          {Map.put(booked, "combat_last", last(booked, exchange)), events}

        _ ->
          {carried_world, []}
      end

    outcome =
      case {Map.get(board, :outcome), exchange} do
        {record, ex} when is_map(record) and is_map(ex) -> Map.put(record, "combat", ex)
        {record, _} -> record
      end

    %{board | world: world, events: board.events ++ events}
    |> Map.put(:outcome, outcome)
  end

  # The play page shows the last exchange (QA 2026-10-14 08:57, #270).
  defp last(world, exchange) do
    %{"tick" => world["world_tick"], "text" => Combat.summary(exchange)}
  end
end
