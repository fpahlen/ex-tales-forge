defmodule TalesForge.World.Instance do
  @moduledoc """
  One process per active session (refactor step 10f, PR 1;
  `docs/design-gc-10f-one-process.md`). The session id is the world id
  until persistent worlds exist.

  It serializes the session's turns: `run_turn/2` queues a
  `TalesForge.World.TurnRequest`, and the instance runs one request at a
  time, first in first out, each in a Task under
  `TalesForge.World.TaskSupervisor`, so its mailbox stays free while the GM
  call runs. The Task is linked to the instance: when the instance dies, the
  turn dies with it and its transaction rolls back, and the caller gets an
  error. The turn job does not retry it (`TalesForge.Workers.ProcessTurn`).

  The instance is started on the first `run_turn/2` under
  `TalesForge.World.Supervisor` (`restart: :transient`), registered in
  `TalesForge.World.Registry` as `{:instance, session_id}`, and stops after
  15 minutes without work (`config :ex_tales_forge, :world_instance_idle_ms`).
  It is not started at boot.

  Once a turn has committed, the instance broadcasts the NPCs that spoke up
  in it (`:npc_initiatives` in the turn's payload,
  `TalesForge.GameCharacter.Initiative.broadcast/2`), after the turn's own
  `{:turn_completed, _}`.

  Its state is a cache, never the truth: the world tick and the session's
  GameCharacters, read from Postgres when it starts and after every turn.
  Nothing reads the cache yet.
  """

  use GenServer

  require Logger

  alias TalesForge.Game.TurnProcessor
  alias TalesForge.GameCharacter
  alias TalesForge.GameCharacter.{Initiative, Store}
  alias TalesForge.Repo
  alias TalesForge.Schemas.GameSession
  alias TalesForge.World.TurnRequest

  @idle_ms :timer.minutes(15)
  # Covers the GM call and its JSON retry.
  @call_timeout :timer.seconds(180)

  defstruct [
    :session_id,
    :world_tick,
    :running,
    :idle_timer,
    characters: [],
    queue: :queue.new()
  ]

  @type t :: %__MODULE__{}

  @doc false
  @spec child_spec(Ecto.UUID.t()) :: Supervisor.child_spec()
  def child_spec(session_id) do
    %{
      id: {__MODULE__, session_id},
      start: {__MODULE__, :start_link, [session_id]},
      restart: :transient
    }
  end

  @doc false
  @spec start_link(Ecto.UUID.t()) :: GenServer.on_start()
  def start_link(session_id),
    do: GenServer.start_link(__MODULE__, session_id, name: via(session_id))

  @doc "The instance's registered name."
  @spec via(Ecto.UUID.t()) :: {:via, Registry, {module(), {:instance, Ecto.UUID.t()}}}
  def via(session_id), do: {:via, Registry, {TalesForge.World.Registry, {:instance, session_id}}}

  @doc "The running instance of the session, or nil."
  @spec whereis(Ecto.UUID.t()) :: pid() | nil
  def whereis(session_id) do
    case Registry.lookup(TalesForge.World.Registry, {:instance, session_id}) do
      [{pid, _}] -> pid
      [] -> nil
    end
  end

  @doc """
  Runs the turn after the session's turns queued before it, and returns what
  `TurnProcessor.run/3` returned; a turn that raised raises again here, with
  its stacktrace, as it did in the caller before. Starts the instance when
  none runs. An instance or Task that dies gives
  `{:error, {:turn_down, reason}}`.
  """
  @spec run_turn(Ecto.UUID.t(), TurnRequest.t()) :: {:ok, map()} | {:error, term()}
  def run_turn(session_id, %TurnRequest{session_id: session_id} = request) do
    case session_id |> ensure_started() |> GenServer.call({:run_turn, request}, @call_timeout) do
      {:played, result, rand} ->
        if rand != :undefined, do: :rand.seed(rand)
        result

      {:crashed, kind, reason, stacktrace} ->
        :erlang.raise(kind, reason, stacktrace)

      {:error, _} = error ->
        error
    end
  catch
    :exit, reason -> {:error, {:turn_down, reason}}
  end

  defp ensure_started(session_id) do
    case DynamicSupervisor.start_child(TalesForge.World.Supervisor, {__MODULE__, session_id}) do
      {:ok, pid} -> pid
      {:error, {:already_started, pid}} -> pid
    end
  end

  @impl true
  def init(session_id) do
    Process.flag(:trap_exit, true)
    {:ok, %__MODULE__{session_id: session_id}, {:continue, :load}}
  end

  @impl true
  def handle_continue(:load, state), do: {:noreply, state |> load() |> idle()}

  @impl true
  def handle_call({:run_turn, %TurnRequest{} = request}, from, state) do
    state = %{state | queue: :queue.in({request, from}, state.queue)}
    {:noreply, state |> cancel_idle() |> next()}
  end

  @impl true
  def handle_info({ref, result}, %__MODULE__{running: {ref, from}} = state) do
    Process.demonitor(ref, [:flush])
    announce(state.session_id, result)
    GenServer.reply(from, result)
    {:noreply, %{state | running: nil} |> load() |> next()}
  end

  def handle_info({:DOWN, ref, :process, _pid, reason}, %__MODULE__{running: {ref, from}} = state) do
    Logger.warning("world turn down session=#{state.session_id} reason=#{inspect(reason)}")
    GenServer.reply(from, {:error, {:turn_down, reason}})
    {:noreply, %{state | running: nil} |> next()}
  end

  def handle_info({:EXIT, _pid, _reason}, state), do: {:noreply, state}

  def handle_info({:idle, ref}, %__MODULE__{running: nil, idle_timer: {ref, _timer}} = state) do
    if :queue.is_empty(state.queue), do: {:stop, :normal, state}, else: {:noreply, state}
  end

  def handle_info({:idle, _stale}, state), do: {:noreply, state}

  # Starts the next queued turn when none runs; idles when none is queued.
  defp next(%__MODULE__{running: nil} = state) do
    case :queue.out(state.queue) do
      {{:value, {request, from}}, queue} ->
        task = Task.Supervisor.async(TalesForge.World.TaskSupervisor, fn -> play(request) end)
        %{state | queue: queue, running: {task.ref, from}}

      {:empty, _queue} ->
        idle(state)
    end
  end

  defp next(state), do: state

  # The turn, as if it ran in the asking process (`TurnRequest`).
  defp play(%TurnRequest{} = request) do
    Process.put(:"$callers", request.callers)
    Logger.metadata(request.logger)
    if request.rand != :undefined, do: :rand.seed(request.rand)

    result =
      TurnProcessor.run(
        request.session_id,
        {request.raw_action, request.player_action},
        request.opts
      )

    {:played, result, :rand.export_seed()}
  catch
    kind, reason -> {:crashed, kind, reason, __STACKTRACE__}
  end

  # The NPCs that spoke up in a committed turn.
  defp announce(session_id, {:played, {:ok, %{npc_initiatives: initiatives}}, _rand}),
    do: Enum.each(initiatives, &Initiative.broadcast(session_id, &1))

  defp announce(_session_id, _result), do: :ok

  defp load(%__MODULE__{session_id: session_id} = state) do
    case Repo.get(GameSession, session_id) do
      %GameSession{world_state: world} ->
        characters =
          session_id |> Store.list_for_session() |> Enum.map(&GameCharacter.from_schema/1)

        %{state | world_tick: Map.get(world || %{}, "world_tick"), characters: characters}

      nil ->
        state
    end
  end

  defp idle(state) do
    state = cancel_idle(state)
    idle_ms = Application.get_env(:ex_tales_forge, :world_instance_idle_ms, @idle_ms)
    ref = make_ref()
    %{state | idle_timer: {ref, Process.send_after(self(), {:idle, ref}, idle_ms)}}
  end

  defp cancel_idle(%__MODULE__{idle_timer: nil} = state), do: state

  defp cancel_idle(%__MODULE__{idle_timer: {_ref, timer}} = state) do
    Process.cancel_timer(timer)
    %{state | idle_timer: nil}
  end
end
