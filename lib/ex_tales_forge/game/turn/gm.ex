defmodule TalesForge.Game.Turn.Gm do
  @moduledoc """
  Stage 6 of a turn: the GM narration. It starts after
  `TalesForge.Game.Turn.Npcs.react/1` and streams each text chunk to the
  `stream` adapter. Writes `narration`: `{:ok, gm_result}` or
  `{:error, reason}`.
  """

  alias TalesForge.AICalls.Steps
  alias TalesForge.Game.Turn

  @doc "Writes `narration`."
  @spec narrate(Turn.t()) :: Turn.t()
  def narrate(%Turn{adapters: adapters, session: session} = turn) do
    narration =
      Steps.time(:gm, fn ->
        adapters.gm.(turn.prompt.messages, turn.intent, turn.outcome.handler, turn.number,
          session_id: session.id,
          on_text: &adapters.stream.(session.id, &1)
        )
      end)

    %{turn | narration: narration}
  end
end
