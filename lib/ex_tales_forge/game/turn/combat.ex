defmodule TalesForge.Game.Turn.Combat do
  @moduledoc """
  The opposed combat steps of stage 3 (`TalesForge.Game.Turn.Mechanics`),
  only with `COMBAT_OPPOSED=on`. The math is in `TalesForge.Game.Combat`.

    * `target/3` — before the roll: finds the person that the attack is aimed
      at. An unclear target blocks the action, and the turn asks the player.
    * `exchange/3` — after the roll: the player's d100 is the attack, and the
      defender may counterattack.
    * `book/2` — after the board: writes the defender's wounds to its
      character in the turn's cast (`board.cast`, a new minor foe joins
      it), writes the exchange to the outcome record and adds the
      `npc.down` or `npc.dead` event.

  NPC fighters and the character rules come from the `fighter` and
  `character_rules` adapters. The rolls come from `opts[:combat_rolls]` in
  tests, otherwise from `:rand`.
  """

  alias TalesForge.Characters.Defaults
  alias TalesForge.Game.Combat
  alias TalesForge.Game.Schemas.{HandlerResult, PlayerAction}
  alias TalesForge.Game.Turn
  alias TalesForge.GameCharacter

  defmodule Fight do
    @moduledoc """
    What `TalesForge.Game.Turn.Combat.exchange/3` returns: the `exchange`
    (or nil) and the minor `foe` fighter when the server made one.
    """
    defstruct [:exchange, :foe]

    @typedoc "An exchange and the minor foe the server made, if any."
    @type t :: %__MODULE__{exchange: map() | nil, foe: TalesForge.GameCharacter.t() | nil}
  end

  @doc "True when opposed combat is on for `turn`."
  @spec on?(Turn.t()) :: boolean()
  def on?(turn), do: Turn.flag?(turn, :combat_opposed)

  @doc """
  The target of a combat roll. Returns `{played, handler, target}`. For an
  unclear target, the handler is a rejected `narrate` handler that asks the
  player, the played action has no skill, and the target is
  `{:unclear, names}`. Without a combat roll, the target is nil.
  """
  @spec target(Turn.t(), PlayerAction.t(), HandlerResult.t()) ::
          {PlayerAction.t(), HandlerResult.t(), Combat.target() | nil}
  def target(turn, played, handler) do
    if on?(turn) and combat_roll?(handler) do
      text = target_text(played, turn.raw_action)

      case Combat.target(played.action.target, text, {Turn.world_before(turn), turn.cast}) do
        {:unclear, names} -> {unrolled(played), ask(names), {:unclear, names}}
        found -> {played, handler, found}
      end
    else
      {played, handler, nil}
    end
  end

  # A target the player picked from the "whom?" question
  # (`IntentClarification.combat_target/3`) counts as named in the text.
  defp target_text(%PlayerAction{action: %{parameters: %{"target_chosen" => true}} = action}, raw)
       when is_binary(action.target),
       do: "#{raw} #{String.replace(action.target, "_", " ")}"

  defp target_text(_played, raw), do: raw

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
  The exchange for `target`, with the player's d100 from `mechanical`, in
  a `Fight`. Its `foe` is the minor foe fighter when the server made one.
  For an unclear target the exchange is `%{"target_unclear" => names}`; it
  is nil without a target or a roll.
  """
  @spec exchange(Turn.t(), Combat.target() | nil, map()) :: Fight.t()
  def exchange(_turn, {:unclear, names}, _mechanical),
    do: %Fight{exchange: %{"target_unclear" => names}}

  def exchange(_turn, nil, _mechanical), do: %Fight{}
  def exchange(_turn, _target, %{roll: nil}), do: %Fight{}

  def exchange(turn, target, mechanical) do
    {defender, foe} = defender(turn, target)
    character = Map.get(Turn.world_before(turn), "character", %{})

    # The attacker is the character as it is, with its own id (10c-c).
    player =
      character
      |> Map.put("name", character["name"] || "the character")
      |> GameCharacter.from_sheet()

    %Fight{
      exchange: Combat.exchange({player, defender}, mechanical.skill, rolls(turn, mechanical)),
      foe: foe
    }
  end

  # A minor foe of the cast fights as it is. Another person fights with the
  # fighter profile and the wounds of its character.
  defp defender(turn, {:npc, id}) do
    case turn.cast[id] do
      %GameCharacter{minor: true} = foe -> {foe, nil}
      member -> fighter(turn, id, member)
    end
  end

  defp defender(turn, {:foe, id, name}), do: new_foe(turn, id, name)

  defp fighter(turn, id, member) do
    case turn.adapters.fighter.(turn.session.id, id) do
      nil ->
        new_foe(turn, id, (member && member.name) || id)

      profile ->
        {profile |> Map.merge(wounds(member)) |> GameCharacter.from_sheet(), nil}
    end
  end

  defp wounds(%GameCharacter{} = member),
    do: member |> GameCharacter.to_sheet() |> Map.take(~w(wounds vitality))

  defp wounds(nil), do: %{}

  defp new_foe(turn, id, name) do
    rules = turn.adapters.character_rules.(Turn.world_before(turn)["adventure_id"])
    foe = Combat.minor_foe({id, name}, rules, Defaults.seed(turn.session.id, id))
    {foe, foe}
  end

  defp rolls(turn, mechanical) do
    forced = qa_rolls(turn)
    injected = turn.opts |> Keyword.get(:combat_rolls, %{}) |> Map.merge(forced)

    %{
      attack: Map.get(injected, :attack, mechanical.roll),
      counter_chance: Map.get_lazy(injected, :counter_chance, &:rand.uniform/0),
      counter: Map.get_lazy(injected, :counter, fn -> :rand.uniform(100) end),
      death: Map.get_lazy(injected, :death, fn -> :rand.uniform(100) end),
      qa_forced: forced != %{}
    }
  end

  @doc """
  The forced combat rolls for QA, playtest only (QA 2026-10-15: Gentry could
  not test critical hits and misses). An admin sets them in the session's
  world_state JSON (admin, session page):

      "qa_rolls": {"attack": 1, "death": 100}

  `attack` is the player's attack d100 (1 is a critical hit when the attack
  target is above 10; 100 is a critical miss), `death` the death roll on a
  downed defender. Each value must be 1 to 100. They stay until the admin
  removes them. On any other role than playtest they do nothing.
  """
  @spec qa_rolls(Turn.t()) :: %{optional(:attack | :death) => 1..100}
  def qa_rolls(%Turn{role: :playtest} = turn) do
    case Map.get(Turn.world_before(turn), "qa_rolls") do
      %{} = rolls ->
        for {key, atom} <- [{"attack", :attack}, {"death", :death}],
            value = rolls[key],
            is_integer(value) and value in 1..100,
            into: %{},
            do: {atom, value}

      _ ->
        %{}
    end
  end

  def qa_rolls(_turn), do: %{}

  @doc """
  Books the fight on the board: writes the defender's wounds to its
  character in `board.cast` (a new minor foe joins the cast), puts the
  exchange in the outcome record (`"combat"`) and adds the events.
  """
  @spec book(map(), Fight.t()) :: map()
  def book(board, %Fight{exchange: %{"attack" => _} = exchange, foe: foe}) do
    {cast, events} = Combat.book(board.cast, board.world, {exchange, foe})
    world = Map.put(board.world, "combat_last", last(board.world, exchange))

    %{board | world: world, events: board.events ++ events}
    |> Map.put(:cast, cast)
    |> Map.put(:outcome, with_combat(Map.get(board, :outcome), exchange))
  end

  def book(board, %Fight{exchange: exchange}),
    do: Map.put(board, :outcome, with_combat(Map.get(board, :outcome), exchange))

  defp with_combat(record, exchange) when is_map(record) and is_map(exchange),
    do: Map.put(record, "combat", exchange)

  defp with_combat(record, _exchange), do: record

  # The play page shows the last exchange (QA 2026-10-14 08:57, #270).
  defp last(world, exchange) do
    %{
      "tick" => world["world_tick"],
      "location_id" => world["location_id"],
      "text" => Combat.summary(exchange)
    }
  end
end
