defmodule Mix.Tasks.E2e.Smoke do
  @moduledoc """
  Live end-to-end smoke test against a running dev server and real LLM.

      mix phx.server   # terminal 1
      mix e2e.smoke    # terminal 2

  Writes `priv/playtest/reports/e2e-smoke.json`.
  """
  use Mix.Task

  import Ecto.Query

  alias TalesForge.GameSessions
  alias TalesForge.LLM
  alias TalesForge.Repo
  alias TalesForge.Schemas.Turn

  @shortdoc "Run live E2E smoke test (requires mix phx.server + XAI_API_KEY)"

  @scenario [
    %{step: 1, action: "look around the tavern"},
    %{step: 2, action: "I ask Marta what the chalk marks mean"},
    %{step: 3, action: "I head outside to Crossroads Square"}
  ]

  @turn_timeout_ms 90_000
  @poll_interval_ms 500
  @mock_marker "_Mock GM:"

  @impl Mix.Task
  def run(_args) do
    Mix.Task.run("app.start")
    started_at = DateTime.utc_now()

    preflight = run_preflight()

    if preflight.status != :ok do
      write_report(%{
        status: "FAIL",
        started_at: DateTime.to_iso8601(started_at),
        preflight: preflight,
        steps: [],
        warnings: Map.get(preflight, :warnings, [])
      })

      System.halt(1)
    end

    Mix.shell().info("E2E smoke: starting tavern scenario (#{length(@scenario)} turns)")

    {:ok, session} = GameSessions.create_session(%{name: "E2E Smoke #{started_at}"})

    {steps, warnings} =
      Enum.map_reduce(@scenario, [], fn %{step: step_num, action: action}, warns ->
        run_step(session.id, step_num, action, warns)
      end)

    status = if Enum.all?(steps, &(&1.status == "PASS")), do: "PASS", else: "FAIL"

    report = %{
      status: status,
      started_at: DateTime.to_iso8601(started_at),
      finished_at: DateTime.to_iso8601(DateTime.utc_now()),
      session_id: session.id,
      llm_provider: TalesForge.Config.llm_provider(),
      llm_source: LLM.llm_source(LLM.provider()),
      preflight: preflight,
      steps: steps,
      warnings: warnings
    }

    write_report(report)
    print_summary(report)

    if status == "FAIL", do: System.halt(1)
  end

  defp run_preflight do
    warnings = []

    warnings =
      if File.exists?(Path.expand(".env")) do
        warnings
      else
        ["missing .env file" | warnings]
      end

    db_ok =
      case Repo.query("SELECT 1") do
        {:ok, _} -> true
        {:error, reason} -> {:error, Exception.message(reason)}
      end

    key = TalesForge.Config.xai_api_key()
    key_ok = key_present?(key)
    provider = TalesForge.Config.llm_provider()

    warnings =
      cond do
        TalesForge.Config.llm_provider() == "mock" ->
          ["LLM_PROVIDER=mock — smoke test expects live API" | warnings]

        provider != "xai" and key_ok ->
          ["LLM provider is #{provider}, expected xai for smoke test" | warnings]

        true ->
          warnings
      end

    server_ok = server_running?()

    checks = %{
      dotenv: File.exists?(Path.expand(".env")),
      database: db_ok == true,
      xai_api_key: key_ok,
      llm_provider: provider,
      server: server_ok
    }

    status =
      if checks.dotenv and checks.database and checks.xai_api_key and checks.server and
           provider != "mock",
         do: :ok,
         else: :error

    if status == :ok do
      Mix.shell().info("[ok] preflight passed (provider=#{provider})")
    else
      Mix.shell().error("[fail] preflight — #{inspect(checks)}")
    end

    %{status: status, checks: checks, warnings: warnings}
  end

  defp run_step(session_id, step_num, action, warnings) do
    started = System.monotonic_time(:millisecond)
    Mix.shell().info("  step #{step_num}: #{action}")

    try do
      submit_step(session_id, step_num, action, started, warnings)
    rescue
      e ->
        latency = System.monotonic_time(:millisecond) - started

        step = %{
          step: step_num,
          action: action,
          status: "FAIL",
          latency_ms: latency,
          error: Exception.message(e)
        }

        Mix.shell().error("    FAIL — #{Exception.message(e)}")
        {step, ["#{action}: #{Exception.message(e)}" | warnings]}
    end
  end

  defp submit_step(session_id, step_num, action, started, warnings) do
    case submit_with_clarification(session_id, action) do
      {:ok, :processing} ->
        case wait_for_turn(session_id, step_num) do
          {:ok, turn, latency_ms} ->
            result = evaluate_turn(step_num, action, turn, latency_ms)
            {result, warnings}

          {:error, reason} ->
            latency = System.monotonic_time(:millisecond) - started

            step = %{
              step: step_num,
              action: action,
              status: "FAIL",
              latency_ms: latency,
              error: inspect(reason)
            }

            Mix.shell().error("    FAIL — #{inspect(reason)}")
            {step, warnings}
        end

      {:error, reason} ->
        latency = System.monotonic_time(:millisecond) - started

        step = %{
          step: step_num,
          action: action,
          status: "FAIL",
          latency_ms: latency,
          error: inspect(reason)
        }

        Mix.shell().error("    FAIL — submit: #{inspect(reason)}")
        {step, warnings}
    end
  end

  defp submit_with_clarification(session_id, action, opts \\ []) do
    case GameSessions.submit_message(session_id, action, opts) do
      {:ok, %{status: :processing}} ->
        {:ok, :processing}

      {:ok, %{status: :clarification, clarification: clarification}} ->
        Mix.shell().info("    clarification needed — picking first option")

        option = List.first(clarification["options"])

        if option do
          submit_with_clarification(session_id, "",
            clarification_id: clarification["clarification_id"],
            option_id: option["id"]
          )
        else
          {:error, :no_clarification_options}
        end

      {:error, _} = err ->
        err
    end
  end

  defp wait_for_turn(session_id, turn_number) do
    deadline = System.monotonic_time(:millisecond) + @turn_timeout_ms
    wait_for_turn(session_id, turn_number, deadline, System.monotonic_time(:millisecond))
  end

  defp wait_for_turn(session_id, turn_number, deadline, started) do
    case fetch_turn(session_id, turn_number) do
      {:ok, turn} ->
        latency = System.monotonic_time(:millisecond) - started
        {:ok, turn, latency}

      :not_found ->
        if System.monotonic_time(:millisecond) >= deadline do
          {:error, :timeout}
        else
          Process.sleep(@poll_interval_ms)
          wait_for_turn(session_id, turn_number, deadline, started)
        end
    end
  end

  defp fetch_turn(session_id, turn_number) do
    turn =
      Turn
      |> where([t], t.game_session_id == ^session_id and t.turn_number == ^turn_number)
      |> Repo.one()

    if turn, do: {:ok, turn}, else: :not_found
  end

  defp evaluate_turn(step_num, action, turn, latency_ms) do
    narrative = turn.narrative || ""
    mock? = String.contains?(narrative, @mock_marker)
    empty? = String.trim(narrative) == ""
    llm_source = LLM.llm_source(LLM.provider())

    issues =
      []
      |> then(fn i -> if empty?, do: ["empty narrative" | i], else: i end)
      |> then(fn i -> if mock?, do: ["mock GM narration" | i], else: i end)
      |> then(fn i -> if llm_source != "api", do: ["llm_source=#{llm_source}" | i], else: i end)

    status = if issues == [], do: "PASS", else: "FAIL"

    step = %{
      step: step_num,
      action: action,
      status: status,
      latency_ms: latency_ms,
      turn_number: turn.turn_number,
      narrative_preview: String.slice(narrative, 0, 200),
      mechanical: turn.mechanical_resolution,
      llm_source: llm_source,
      issues: issues
    }

    if status == "PASS" do
      Mix.shell().info("    PASS — #{latency_ms}ms, #{String.length(narrative)} chars")
    else
      Mix.shell().error("    FAIL — #{Enum.join(issues, ", ")}")
    end

    step
  end

  defp server_running? do
    case Req.get("http://localhost:4000", receive_timeout: 5_000) do
      {:ok, %{status: status}} when status in 200..399 -> true
      _ -> false
    end
  rescue
    _ -> false
  end

  defp write_report(report) do
    path = Path.expand("priv/playtest/reports/e2e-smoke.json")
    File.mkdir_p!(Path.dirname(path))
    File.write!(path, Jason.encode!(report, pretty: true))
    Mix.shell().info("Report written to #{path}")
  end

  defp print_summary(%{status: status, steps: steps, warnings: warnings}) do
    Mix.shell().info("")
    Mix.shell().info("E2E smoke: #{status}")

    for step <- steps do
      Mix.shell().info("  step #{step.step}: #{step.status} (#{step.latency_ms}ms)")
    end

    for warning <- warnings do
      Mix.shell().info("  warning: #{warning}")
    end
  end

  defp key_present?(value), do: is_binary(value) and String.trim(value) != ""
end
