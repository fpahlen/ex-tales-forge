defmodule TalesForge.GameSessions do
  @moduledoc """
  Coordinates database sessions with Jido player session agents.
  """

  import Ecto.Query

  alias Jido.AgentServer
  alias Jido.Signal
  alias TalesForge.Agents.PlayerSessionAgent
  alias TalesForge.PubSub.GameSession, as: SessionPubSub
  alias TalesForge.Repo
  alias TalesForge.Schemas.GameSession
  alias TalesForge.Schemas.Turn

  def list_sessions do
    GameSession
    |> order_by([s], desc: s.inserted_at)
    |> Repo.all()
  end

  def get_session!(id), do: Repo.get!(GameSession, id)

  def create_session(attrs \\ %{}) do
    attrs =
      Map.merge(
        %{
          name: "New Adventure",
          status: "active",
          world_state: default_world_state()
        },
        attrs
      )

    with {:ok, session} <-
           %GameSession{}
           |> GameSession.changeset(attrs)
           |> Repo.insert(),
         :ok <- ensure_agent(session) do
      {:ok, session}
    end
  end

  def submit_message(session_id, text) when is_binary(text) do
    trimmed = String.trim(text)

    if trimmed == "" do
      {:error, :empty_message}
    else
      with {:ok, pid} <- ensure_agent_pid(session_id),
           {:ok, agent} <- deliver_player_message(pid, trimmed) do
        state = agent_state(agent)

        with {:ok, _turn} <- persist_turn(session_id, trimmed, state) do
          SessionPubSub.broadcast(session_id, {:turn_completed, state})
          {:ok, state}
        end
      end
    end
  end

  def agent_id(session_id), do: "session-#{session_id}"

  def ensure_agent_started(%GameSession{id: id}) do
    ensure_agent(%GameSession{id: id})
  end

  defp ensure_agent(%GameSession{id: id}) do
    case start_agent(id) do
      {:ok, _pid} -> :ok
      other -> other
    end
  end

  defp ensure_agent_pid(session_id) do
    aid = agent_id(session_id)

    case TalesForge.Jido.whereis(aid) do
      nil ->
        with {:ok, session} <- fetch_session(session_id),
             :ok <- ensure_agent(session),
             pid when not is_nil(pid) <- TalesForge.Jido.whereis(aid) do
          {:ok, pid}
        else
          nil -> {:error, :agent_unavailable}
          {:error, _} = err -> err
        end

      pid ->
        {:ok, pid}
    end
  end

  defp start_agent(session_id) do
    case TalesForge.Jido.start_agent(PlayerSessionAgent,
           id: agent_id(session_id),
           initial_state: %{
             session_id: session_id,
             turn_count: 0,
             entries: []
           }
         ) do
      {:ok, pid} -> {:ok, pid}
      {:error, {:already_started, pid}} -> {:ok, pid}
      other -> other
    end
  end

  defp agent_state(%{state: state}), do: state
  defp agent_state(state) when is_map(state), do: state

  defp deliver_player_message(pid, text) do
    signal =
      Signal.new!(
        "player.message",
        %{text: text},
        source: "/tales_forge/liveview"
      )

    AgentServer.call(pid, signal)
  end

  defp persist_turn(session_id, player_text, %{turn_count: turn_count, entries: entries}) do
    gm_entry = entries |> Enum.reverse() |> Enum.find(&(&1.role == "gm"))

    attrs = %{
      game_session_id: session_id,
      turn_number: turn_count,
      player_action: player_text,
      narrative: gm_entry && gm_entry.text,
      mechanical_resolution: %{}
    }

    %Turn{}
    |> Turn.changeset(attrs)
    |> Repo.insert()
  end

  defp fetch_session(session_id) do
    case Repo.get(GameSession, session_id) do
      nil -> {:error, :not_found}
      session -> {:ok, session}
    end
  end

  defp default_world_state do
    %{
      "location_id" => "crossroads_hamlet_tavern",
      "location_name" => "The Ledger & Ladle",
      "world_clock" => "late afternoon",
      "character" => %{
        "name" => "Elara Voss",
        "wounds" => 0,
        "wound_max" => 3,
        "coins" => %{"gold" => 2, "silver" => 10, "copper" => 0}
      }
    }
  end
end
