defmodule TalesForge.Workers.ProcessTurn do
  @moduledoc """
  Oban worker for Tier 2 GM narration and turn persistence.

  Core runtime path. Uses Ecto-only game modules.

  One attempt (`max_attempts: 1`). A turn that fails has already told the
  player (`TalesForge.Game.TurnProcessor` broadcasts `:turn_failed` for an
  error and for a crash), so the job must not run the turn again: a second
  attempt streamed new GM text onto a page that showed "Turn failed", and it
  could commit a turn the player did not expect (or two, when they pressed
  Act again). The player retries by acting again. The GM call keeps its own
  JSON-correction retry inside the attempt (`TalesForge.LLM`).
  """
  use Oban.Worker, queue: :llm, max_attempts: 1

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
