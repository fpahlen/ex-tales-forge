defmodule TalesForge.Game.Turn.Prompt do
  @moduledoc """
  Stage 5 of a turn: the GM context and the GM messages
  (`TalesForge.Game.Prompts.gm_messages/3`, built by `TalesForge.Prompt`).
  Writes `prompt`: `context` and `messages`.
  """

  alias TalesForge.AICalls.Steps
  alias TalesForge.Game.ActionHandler
  alias TalesForge.Game.Context
  alias TalesForge.Game.Progression
  alias TalesForge.Game.Prompts
  alias TalesForge.Game.Schemas.PlayerAction
  alias TalesForge.Game.Turn

  @doc "Writes `prompt`."
  @spec build(Turn.t()) :: Turn.t()
  def build(%Turn{outcome: outcome, session: session} = turn) do
    Steps.time(:prompt, fn ->
      context =
        %{session | world_state: outcome.board.world}
        |> Context.build_gm_context()
        |> Map.put(:npc_reactions, turn.npcs.reactions)
        |> Map.put(:world_facts, outcome.agents)
        |> Map.put(:price_lines, outcome.price_lines)
        |> Map.put(:moved_from, moved_from(session.world_state, outcome.board.world))
        |> Map.put(:premise_findings, turn.premise.findings)
        |> Map.put(:outcome_record, Map.get(outcome.board, :outcome))
        |> Map.put(:rest_growth, rest_growth(outcome))
        |> Map.put(:noticed, turn.notice)
        |> Map.put(:combat, Map.get(outcome, :combat))
        |> put_player_request(turn.opts[:gm_note])

      messages =
        Prompts.gm_messages(context, gm_turn(turn), flags: turn.flags, role: turn.role)

      %{turn | prompt: %{context: context, messages: messages}}
    end)
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

  # The location the character left this turn, or nil (the scene block in
  # the GM prompt narrates the move from it).
  defp moved_from(before, after_board) do
    from = Map.get(before || %{}, "location_id")
    if from != Map.get(after_board, "location_id"), do: from
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

  # INTENT_JEV=on: the GM's quote replaces overall_intent in the prompt only.
  defp gm_action(player_action, quote) when is_binary(quote) and quote != "",
    do: %PlayerAction{player_action | overall_intent: quote}

  defp gm_action(player_action, _quote), do: player_action
end
