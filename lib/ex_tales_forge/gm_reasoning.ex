defmodule TalesForge.GMReasoning do
  @moduledoc """
  The GM's raw JSON reply for each turn, stored as a player-unaware
  `gm_reasoning` session event with the turn's number and world tick.
  `TalesForge.Playtest.CharacterChanges` reads it (the GM's NPC memory
  updates, and the tick that places a memory on a turn) and
  `TalesForge.Playtest.Reports` reads its tick to place the turn's other
  session events. Never shown to the player, never fed back into a prompt.
  """

  require Logger

  import Ecto.Query

  alias TalesForge.Game.Schemas.GMStructuredResponse
  alias TalesForge.Repo
  alias TalesForge.Schemas.SessionEvent

  @kind "gm_reasoning"

  defmodule At do
    @moduledoc "Where a reasoning event goes: the session and the world tick (nil counts as 0)."
    defstruct [:session_id, :tick]

    @typedoc "The session and world tick of a reasoning event."
    @type t :: %__MODULE__{session_id: Ecto.UUID.t(), tick: integer() | nil}
  end

  @doc "Adds a `:gm_reasoning` step after `:turn`. A failed insert is logged and never aborts the turn."
  @spec multi_insert(Ecto.Multi.t(), At.t(), GMStructuredResponse.t()) :: Ecto.Multi.t()
  def multi_insert(multi, %At{} = at, %GMStructuredResponse{} = gm_result) do
    Ecto.Multi.run(multi, :gm_reasoning, fn _repo, %{turn: turn} ->
      {:ok, insert(at, turn, gm_result)}
    end)
  end

  @doc "A session's reasoning events, ordered by turn."
  def list_for_session(session_id) do
    SessionEvent
    |> where([e], e.game_session_id == ^session_id and e.kind == @kind)
    |> order_by([e], asc: fragment("(?->>'turn_number')::int", e.payload), asc: e.inserted_at)
    |> Repo.all()
  end

  defp insert(%At{session_id: session_id} = at, turn, gm_result) do
    %SessionEvent{}
    |> SessionEvent.changeset(%{
      game_session_id: session_id,
      kind: @kind,
      actor: "gm",
      player_aware: false,
      tick: at.tick || 0,
      payload: %{
        "turn_id" => turn.id,
        "turn_number" => turn.turn_number,
        "gm_reply" => gm_result.raw
      }
    })
    |> Repo.insert_isolated()
    |> case do
      {:ok, event} ->
        event

      {:error, changeset} ->
        Logger.warning(
          "gm reasoning not stored session=#{session_id} errors=#{inspect(changeset.errors)}"
        )

        nil
    end
  rescue
    e ->
      Logger.warning(
        "gm reasoning not stored session=#{session_id} error=#{Exception.message(e)}"
      )

      nil
  end
end
