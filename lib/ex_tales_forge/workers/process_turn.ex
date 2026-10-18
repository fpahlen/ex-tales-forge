defmodule TalesForge.Workers.ProcessTurn do
  @moduledoc """
  Oban worker for Tier 2 GM narration and turn persistence.

  Core runtime path. Uses Ecto-only game modules.
  """
  use Oban.Worker, queue: :llm, max_attempts: 3

  alias TalesForge.World.{Instance, TurnRequest}

  @impl Oban.Worker
  def perform(%Oban.Job{
        args:
          %{
            "session_id" => session_id,
            "raw_action" => raw_action,
            "player_action" => player_action
          } = args
      }) do
    # gm_quote / gm_note: set only by the Jev intent path (INTENT_JEV=on,
    # TalesForge.IntentJev); absent otherwise, so the turn is exactly today's.
    # founder: the signed-in founder who played the turn (work log), or absent.
    gm = [gm_quote: args["gm_quote"], gm_note: args["gm_note"], founder: args["founder"]]

    request = TurnRequest.new(session_id, {raw_action, player_action}, gm)

    # One turn at a time per session (refactor step 10f, PR 1).
    case Instance.run_turn(session_id, request) do
      {:ok, _payload} -> :ok
      {:error, {:spend_cap, _kind} = reason} -> {:cancel, reason}
      {:error, reason} -> {:error, reason}
    end
  end
end
