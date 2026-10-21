defmodule TalesForge.Game.Turn.Prompt do
  @moduledoc """
  Stage 5 of a turn: the GM context and the GM messages
  (`TalesForge.Prompt.Assemble.gm_messages/3`, built by `TalesForge.Prompt`).
  Writes `prompt`: `context` and `messages`.
  """

  alias TalesForge.AICalls.Steps
  alias TalesForge.Game.ActionHandler
  alias TalesForge.Game.Context
  alias TalesForge.Game.Progression
  alias TalesForge.Game.Prompts
  alias TalesForge.Game.Schemas.PlayerAction
  alias TalesForge.Game.Turn
  alias TalesForge.Game.Turn.NarratedArrival
  alias TalesForge.Locations
  alias TalesForge.Prompt.Assemble

  @doc "Writes `prompt`."
  @spec build(Turn.t()) :: Turn.t()
  def build(%Turn{outcome: outcome, session: session} = turn) do
    Steps.time(:prompt, fn ->
      context =
        %{session | world_state: outcome.board.world}
        |> Context.build_gm_context(outcome.board.cast)
        |> Map.merge(turn_context(turn))
        |> put_player_request(turn.opts[:gm_note])
        |> put_clarify(turn.intent.clarify)

      messages =
        Assemble.gm_messages(context, gm_turn(turn), flags: turn.flags, role: turn.role)

      %{turn | prompt: %{context: context, messages: messages}}
    end)
  end

  # What this turn adds to the GM context: the NPC reactions, the world facts,
  # the prices, the move, the premise findings, the outcome record, the rest
  # growth, what the character noticed and the combat exchange.
  defp turn_context(%Turn{outcome: outcome, session: session} = turn) do
    %{
      npc_reactions: turn.npcs.reactions,
      world_facts: outcome.agents,
      price_lines: outcome.price_lines,
      moved_from: NarratedArrival.from(session.world_state, outcome.board.world),
      arrived: (session.world_state || %{})["arrived_npcs"],
      premise_findings: turn.premise.findings,
      outcome_record: Map.get(outcome.board, :outcome),
      rest_growth: rest_growth(outcome),
      noticed: turn.notice,
      combat: Map.get(outcome, :combat),
      surroundings:
        Turn.flag?(turn, :location_grid) && Locations.Prompt.surroundings(outcome.board.world)
    }
  end

  # What the turn adds to the GM prompt: the resolution, the action the GM
  # plays (with the player's quote), the handler and the turn number.
  defp gm_turn(%Turn{outcome: outcome} = turn) do
    %Prompts.GmTurn{
      mechanical: outcome.mechanical,
      player_action: gm_action(Map.get(outcome, :played) || turn.intent, turn.opts[:gm_quote]),
      handler: outcome.handler,
      turn_number: turn.number
    }
  end

  # On a long rest, the improvement attempts the rest resolved and the skills
  # that need reflection first, for the GM's "you wake and feel surer" /
  # "needs reflection" note; on any other turn, a physical skill that improved
  # right away, for the "a little surer at" note.
  defp rest_growth(%{handler: handler, mechanical: mechanical, board: board}) do
    cond do
      long_rest?(handler) ->
        %{
          attempts: mechanical.improvements || [],
          needs_reflection: Map.get(board, :needs_reflection, [])
        }

      Enum.any?(Map.get(board, :turn_growth, []), & &1["improved"]) ->
        %{attempts: board.turn_growth, now: true}

      true ->
        nil
    end
  end

  defp long_rest?(%{handler: "wait"} = handler),
    do: handler |> ActionHandler.tick_delta() |> Progression.long_rest?()

  defp long_rest?(_handler), do: false

  defp put_player_request(context, nil), do: context

  defp put_player_request(context, note) when is_binary(note),
    do: Map.put(context, :player_request, note)

  # An unclear turn: the question the GM voices (`TalesForge.Game.Clarify`).
  defp put_clarify(context, %{} = clarify), do: Map.put(context, :clarify, clarify)
  defp put_clarify(context, _none), do: context

  # INTENT_JEV=on: the GM's quote replaces overall_intent in the prompt only.
  defp gm_action(player_action, quote) when is_binary(quote) and quote != "",
    do: %PlayerAction{player_action | overall_intent: quote}

  defp gm_action(player_action, _quote), do: player_action
end
