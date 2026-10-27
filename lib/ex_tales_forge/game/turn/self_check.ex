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

  alias TalesForge.Game.Schemas.{HandlerResult, PlayerAction, SingleAction}
  alias TalesForge.Game.SelfCheck
  alias TalesForge.Game.StateFacts
  alias TalesForge.Game.Turn

  # The action types that do nothing of their own when they only ask.
  @asking_types [:other, :observe, :freeform, :none_fits]

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
  def only_ask(%HandlerResult{state_hints: hints} = handler, %Turn{} = turn) do
    if only_asks?(turn.intent) and not rejected?(hints) and asks(turn) != [],
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

  defp rejected?(%{"rejected" => true}), do: true
  defp rejected?(_hints), do: false

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
        facts = StateFacts.build(world["character"] || %{})
        line = facts |> SelfCheck.resolve(asks) |> line()
        %{handler | state_hints: Map.put(handler.state_hints || %{}, "self_check", line)}
    end
  end

  defp line(%SelfCheck.Result{coins: coins, pack: pack}) do
    facts = [{"Coins", coins}, {"Pack", pack}] |> Enum.reject(&is_nil(elem(&1, 1)))

    "Narrator, not an NPC: the player asks about their own " <>
      Enum.map_join(facts, " and ", fn {name, _} -> String.downcase(name) end) <>
      ". " <>
      Enum.map_join(facts, " ", fn {name, text} -> "#{name}: #{text}." end) <>
      " State these facts as the narrator, as they are after this turn's action; " <>
      "no character in the scene answers or comments on them."
  end
end
