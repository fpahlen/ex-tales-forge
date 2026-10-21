defmodule TalesForge.LocationTurns do
  @moduledoc """
  Plays turns with LOCATION_GRID on through the whole turn pipe, for the
  location tests. The intent is a reading (`{text, action_type, target}`)
  validated against the session's intent context, as Jev's is.
  """

  alias TalesForge.Game.Context
  alias TalesForge.Game.Intent
  alias TalesForge.Game.Schemas.{GMStructuredResponse, IntentExtraction, SingleAction}
  alias TalesForge.Game.Turn
  alias TalesForge.GameSessions

  @doc "Plays one turn of `session_id` and returns `{turn, gm_prompt}`."
  @spec play(String.t(), {String.t(), atom(), String.t() | nil}) :: {Turn.t(), String.t()}
  def play(session_id, {text, type, target}) do
    session = GameSessions.get_session!(session_id)
    me = self()

    extraction = %IntentExtraction{
      overall_intent: text,
      actions: [%SingleAction{action_type: type, target: target, parameters: %{}}]
    }

    action = Intent.validate_player_action(extraction, Context.build_intent_context(session))

    adapters = %Turn.Adapters{
      gm: fn %TalesForge.LLM.GmTurn{messages: messages} ->
        send(me, {:gm_prompt, Enum.map_join(messages, "\n", & &1.content)})
        {:ok, %GMStructuredResponse{narrative: "You go."}}
      end,
      stream: fn _id, _chunk -> :ok end
    }

    flags = Map.put(Turn.read_flags(), :location_grid, true)

    turn =
      {session, TalesForge.Game.Turn.Store.next_turn_number(session_id)}
      |> Turn.new({text, action}, flags: flags, role: :playtest, adapters: adapters)
      |> Turn.Premise.check()
      |> Turn.Mechanics.apply()
      |> Turn.Reactions.react()
      |> Turn.Place.settle()
      |> Turn.Prompt.build()
      |> Turn.Gm.narrate()
      |> Turn.Outcome.persist()

    receive do
      {:gm_prompt, prompt} -> {turn, prompt}
    after
      0 -> {turn, ""}
    end
  end
end
