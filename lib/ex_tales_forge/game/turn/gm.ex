defmodule TalesForge.Game.Turn.Gm do
  @moduledoc """
  Stage 6 of a turn: the GM narration. It starts after
  `TalesForge.Game.Turn.Npcs.react/1` and streams each text chunk to the
  `stream` adapter. Writes `narration`: `{:ok, gm_result}` or
  `{:error, reason}`.
  """

  alias TalesForge.AICalls.Steps
  alias TalesForge.Game.Turn
  alias TalesForge.LLM.GmTurn

  @doc "Writes `narration`."
  @spec narrate(Turn.t()) :: Turn.t()
  def narrate(%Turn{adapters: adapters, session: session} = turn) do
    narration =
      Steps.time(:gm, fn ->
        adapters.gm.(%GmTurn{
          messages: turn.prompt.messages,
          player_action: turn.intent,
          handler: turn.outcome.handler,
          turn_number: turn.number,
          opts: [session_id: session.id, on_text: &adapters.stream.(session.id, &1)]
        })
      end)

    %{turn | narration: narration}
  end
end
