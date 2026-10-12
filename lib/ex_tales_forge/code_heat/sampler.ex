defmodule TalesForge.CodeHeat.Sampler do
  @moduledoc """
  The hourly task of the code heat map (`TalesForge.CodeHeat`).

  When the heat map is on (`TalesForge.CodeHeat.enabled?/1`), the sampler
  starts call-time tracing of the app's modules (`TalesForge.CodeHeat.Tracer`).
  At each `:read_every_ms` (1 hour) it reads the counters, writes one sample
  with the counts of that hour (`TalesForge.CodeHeat.save/4`) and starts a
  new trace session from zero. When the heat map is off, the sampler does
  not start.

  When the sampler stops (`terminate/2`, for example when Fly stops the
  machine with SIGTERM), it writes one sample with the counts since the last
  sample. Then it stops the trace session. The BEAM also removes the session
  when the sampler process stops.
  """
  use GenServer

  require Logger

  alias TalesForge.CodeHeat
  alias TalesForge.CodeHeat.Tracer

  @doc """
  Starts the sampler. Returns `:ignore` when the heat map is off on this app.
  Options: `:name` (default `#{inspect(__MODULE__)}`), `:modules` (default
  `TalesForge.CodeHeat.traced_modules/0`) and `:force` (start also when the
  heat map is off, for tests).
  """
  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(opts \\ []) do
    if Keyword.get(opts, :force, false) or CodeHeat.enabled?() do
      GenServer.start_link(__MODULE__, opts, name: Keyword.get(opts, :name, __MODULE__))
    else
      :ignore
    end
  end

  @doc """
  Writes one sample now with the counts since the last sample and starts
  again from zero. Returns the result of `TalesForge.CodeHeat.save/4`.
  """
  @spec sample_now(GenServer.server()) :: {:ok, struct()} | {:error, Ecto.Changeset.t()}
  def sample_now(server \\ __MODULE__), do: GenServer.call(server, :sample, 30_000)

  @impl true
  def init(opts) do
    Process.flag(:trap_exit, true)
    modules = Keyword.get_lazy(opts, :modules, &CodeHeat.traced_modules/0)
    {:ok, session} = Tracer.start(modules)

    Logger.info("code_heat started modules=#{length(modules)}")
    schedule(:read, CodeHeat.config(:read_every_ms))

    {:ok, %{session: session, modules: modules, started_at: DateTime.utc_now()}}
  end

  @impl true
  def handle_info(:read, state) do
    schedule(:read, CodeHeat.config(:read_every_ms))
    {_result, state} = sample(state)
    {:noreply, state}
  end

  def handle_info(_message, state), do: {:noreply, state}

  @impl true
  def handle_call(:sample, _from, state) do
    {result, state} = sample(state)
    {:reply, result, state}
  end

  @impl true
  def terminate(_reason, state) do
    {_result, state} = sample(state, restart: false)
    Tracer.stop(state.session)
  end

  # Read the counters, write one sample of them, then start a new session
  # from zero (unless the sampler stops).
  defp sample(state, opts \\ []) do
    started = System.monotonic_time(:microsecond)
    rows = Tracer.read(state.session, state.modules)
    :ok = Tracer.stop(state.session)

    session =
      if Keyword.get(opts, :restart, true) do
        {:ok, session} = Tracer.start(state.modules)
        session
      else
        state.session
      end

    counts =
      Enum.reduce(rows, %{}, fn {m, f, a, calls, time_us}, acc ->
        Map.update(acc, {m, f, a}, {calls, time_us}, fn {c, t} -> {c + calls, t + time_us} end)
      end)

    now = DateTime.utc_now()
    result = CodeHeat.save(counts, state.started_at, now, length(state.modules))

    Logger.info(
      "code_heat sample functions=#{map_size(counts)} " <>
        "duration_ms=#{div(System.monotonic_time(:microsecond) - started, 1000)}"
    )

    {result, %{state | session: session, started_at: now}}
  end

  defp schedule(message, ms), do: Process.send_after(self(), message, ms)
end
