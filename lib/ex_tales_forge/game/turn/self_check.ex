defmodule TalesForge.Game.Turn.SelfCheck do
  @moduledoc """
  A self-check in a turn (`JEV_SELF_CHECK=on`, `TalesForge.Game.SelfCheck`):
  the player asks about their own coins or pack, and the GM answers as the
  narrator from the sheet after the board (h-qa13, h-qa16, h-qa21).

  What is asked comes from Jev's `self_check` answer (the action's
  `"self_check"` parameter) and, when Jev did not read the turn, from the
  narrow text fallback (`TalesForge.Game.SelfCheck.asks/1`). A turn that only
  asks plays no action and costs no time (`only_ask/2`). The answer is a
  state hint on the GM's handler, built from the character after the trade
  (`hint/3`). With the flag off nothing here changes a turn.
  """

  alias TalesForge.Game.Cast
  alias TalesForge.Game.Schemas.{HandlerResult, PlayerAction, SingleAction}
  alias TalesForge.Game.SelfCheck
  alias TalesForge.Game.StateFacts
  alias TalesForge.Game.Turn

  # The action types that do nothing of their own when they only ask. A
  # `speak` with no target is a question to the narrator only when it asks
  # (`asks/1` is not `[]`, checked in `only_ask/2`): a bare one (shouting,
  # announcing) keeps its time. Playtest 6cb0391: Jev read h-qa19 and h-qa23
  # as such a speak.
  @asking_types [:other, :observe, :freeform, :none_fits, :speak]

  # The end of the GM's self-check line (`hint/3`).
  @as_narrator "State these facts as the narrator, as they are after this turn's action; " <>
                 "no character in the scene answers or comments on them."

  @doc """
  What the turn asks about the player's own state: `[]` with the flag off, on
  a clarify turn or an injection turn.
  """
  @spec asks(Turn.t()) :: [SelfCheck.ask()]
  def asks(%Turn{intent: %PlayerAction{clarify: nil} = action, injected: false} = turn) do
    if Turn.flag?(turn, :jev_self_check), do: read(action, turn.raw_action), else: []
  end

  def asks(%Turn{}), do: []

  # Jev's answer when it read the turn, else the text fallback.
  defp read(%PlayerAction{action: %SingleAction{parameters: %{"self_check" => names}}}, _text)
       when is_list(names),
       do: for(ask <- [:coins, :pack], Atom.to_string(ask) in names, do: ask)

  defp read(_action, text), do: SelfCheck.asks(text)

  @doc """
  The handler of a turn that only asks (no target, no other action, nothing
  else to play): a `narrate` handler with no action, so no roll and no time.
  Any other turn keeps `handler`.
  """
  @spec only_ask(HandlerResult.t(), Turn.t()) :: HandlerResult.t()
  def only_ask(%HandlerResult{state_hints: %{"rejected" => true}} = handler, _turn), do: handler

  def only_ask(%HandlerResult{} = handler, %Turn{} = turn) do
    if only_asks?(turn.intent) and asks(turn) != [],
      do: %HandlerResult{
        handler: "narrate",
        notes: "The player only asks about their own coins or pack: no action plays.",
        state_hints: %{"no_action" => true}
      },
      else: handler
  end

  defp only_asks?(%PlayerAction{action: %SingleAction{action_type: type, target: nil}} = action),
    do: type in @asking_types and action.deferred_actions == []

  defp only_asks?(_action), do: false

  @doc """
  The turn with no target when its action is a `speak` to an NPC whom the
  text does not name (`unaddressed/3`) and the turn then only asks: the
  intent the rules, the board, the GM and the stored turn get, so
  `only_ask/2` applies. Any other turn is unchanged.
  """
  @spec address(Turn.t()) :: Turn.t()
  def address(turn) do
    addressed = unaddressed(turn.intent, turn.raw_action, turn.cast)
    if only_asks?(addressed) and asks(turn) != [], do: %{turn | intent: addressed}, else: turn
  end

  @doc """
  `action` with no target when it is a `speak` to an NPC of `cast` whose
  first name `text` does not have as a word, in any case (the full name
  starts with it). Playtest e7b76e5: Jev read h-qa19 and h-qa23, which name
  no one, as a speak to Marta Kellen. Any other action is unchanged.

      iex> cast = %{"marta_kellen" => %TalesForge.GameCharacter{name: "Marta Kellen"}}
      iex> speak = %TalesForge.Game.Schemas.PlayerAction{
      ...>   action: %TalesForge.Game.Schemas.SingleAction{action_type: :speak, target: "marta_kellen"}
      ...> }
      iex> for text <- ["Marta, my coins?", "How much money do I have left?", "Martanna?"],
      ...>   do: TalesForge.Game.Turn.SelfCheck.unaddressed(speak, text, cast).action.target
      ["marta_kellen", nil, nil]
  """
  @spec unaddressed(PlayerAction.t(), String.t(), Cast.t()) :: PlayerAction.t()
  def unaddressed(
        %PlayerAction{action: %SingleAction{action_type: :speak, target: id}} = action,
        text,
        cast
      )
      when is_map_key(cast, id) do
    if named?(text, Cast.name(cast, id)), do: action, else: put_in(action.action.target, nil)
  end

  def unaddressed(%PlayerAction{} = action, _text, _cast), do: action

  defp named?(text, name),
    do: Regex.match?(~r/\b#{Regex.escape(hd(String.split(name)))}\b/iu, text)

  @doc """
  `handler` with the GM's self-check line (`state_hints["self_check"]`),
  answered from the character in `world` (the board's world, after any
  trade). Unchanged when the turn asks nothing.
  """
  @spec hint(HandlerResult.t(), Turn.t(), map()) :: HandlerResult.t()
  def hint(%HandlerResult{} = handler, %Turn{} = turn, world) do
    case asks(turn) do
      [] ->
        handler

      asks ->
        result = SelfCheck.resolve(StateFacts.build(world["character"] || %{}), asks)

        %{
          handler
          | state_hints: Map.put(handler.state_hints || %{}, "self_check", line(result, asks))
        }
    end
  end

  # `asks` and the fields of `result` are both in `[:coins, :pack]` order.
  defp line(%SelfCheck.Result{} = result, asks) do
    asked = Enum.join(asks, " and ")

    stated =
      Enum.map_join(asks, " ", &"#{String.capitalize("#{&1}")}: #{Map.fetch!(result, &1)}.")

    "Narrator, not an NPC: the player asks about their own #{asked}. #{stated} #{@as_narrator}"
  end
end
