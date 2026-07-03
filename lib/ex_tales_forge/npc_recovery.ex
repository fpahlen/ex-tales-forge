defmodule TalesForge.NPCRecovery do
  @moduledoc """
  Restores NPC Jido agents for active sessions after application boot.
  """

  use GenServer

  require Logger

  import Ecto.Query

  alias TalesForge.NPCRegistry
  alias TalesForge.Repo
  alias TalesForge.Schemas.GameSession

  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @doc false
  def recover_now do
    GenServer.call(__MODULE__, :recover)
  end

  @impl true
  def init(_opts) do
    send(self(), :recover)
    {:ok, %{}}
  end

  @impl true
  def handle_info(:recover, state) do
    recover_active_sessions()
    {:noreply, state}
  end

  @impl true
  def handle_call(:recover, _from, state) do
    result = recover_active_sessions()
    {:reply, result, state}
  end

  defp recover_active_sessions do
    started = System.monotonic_time(:millisecond)

    count =
      GameSession
      |> where([s], s.status == "active")
      |> Repo.all()
      |> Enum.reduce(0, fn session, acc ->
        case NPCRegistry.sync(session) do
          :ok -> acc + 1
          _ -> acc
        end
      end)

    elapsed = System.monotonic_time(:millisecond) - started
    Logger.info("npc recovery synced sessions=#{count} duration_ms=#{elapsed}")
    {:ok, count}
  end
end
