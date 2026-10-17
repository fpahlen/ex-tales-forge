defmodule TalesForge.CodeHeatTest do
  use TalesForge.DataCase, async: false

  alias TalesForge.CodeHeat
  alias TalesForge.Repo
  alias TalesForge.Schemas.AICall
  alias TalesForge.Schemas.CodeHeatSnapshot

  doctest TalesForge.CodeHeat

  setup do
    on_exit(fn -> Application.delete_env(:ex_tales_forge, CodeHeat) end)
  end

  defp put_config(opts), do: Application.put_env(:ex_tales_forge, CodeHeat, opts)

  describe "enabled?/1" do
    test "is off by default and always off on production" do
      refute CodeHeat.enabled?(:playtest)
      put_config(enabled: true)
      assert CodeHeat.enabled?(:playtest)
      assert CodeHeat.enabled?(:local)
      refute CodeHeat.enabled?(:production)
    end
  end

  test "traced_modules/0 lists the app's modules without the heat map's own modules" do
    modules = CodeHeat.traced_modules()
    assert TalesForge.AppRole in modules
    refute CodeHeat in modules
    refute CodeHeat.Tracer in modules
    refute Enum.any?(modules, &String.starts_with?(Atom.to_string(&1), "Elixir.Mix.Tasks."))

    put_config(max_modules: 3)
    assert length(CodeHeat.traced_modules()) == 3
  end

  describe "save/2" do
    test "keeps the functions with the most time and the newest samples" do
      put_config(max_rows: 2, keep: 2)
      now = DateTime.utc_now()

      totals = %{
        {TalesForge.AppRole, :role, 1} => {10, 300},
        {TalesForge.AppRole, :playtest?, 1} => {50, 100},
        {TalesForge.LLM, :chat, 2} => {2, 900}
      }

      for i <- 1..3 do
        assert {:ok, _} =
                 CodeHeat.save(totals, %CodeHeat.Sample{
                   started_at: DateTime.add(now, -i, :day),
                   ended_at: DateTime.add(now, i, :second),
                   modules: 7
                 })
      end

      assert Repo.aggregate(CodeHeatSnapshot, :count) == 2
      latest = CodeHeat.latest()
      assert latest.modules == 7

      assert [
               %{"module" => "TalesForge.LLM", "function" => "chat/2", "app" => "ex_tales_forge"},
               _
             ] =
               latest.rows
    end

    test "latest/0 is nil without samples" do
      assert CodeHeat.latest() == nil
    end
  end

  describe "window/1 and merge/3" do
    test "merges the samples of the last 24 hours into one row list" do
      now = DateTime.utc_now()

      for {hours_ago, calls} <- [{30, 100}, {5, 2}, {1, 3}] do
        ended = DateTime.add(now, -hours_ago, :hour)

        {:ok, _} =
          CodeHeat.save(
            %{{TalesForge.AppRole, :role, 1} => {calls, calls * 10}},
            %CodeHeat.Sample{
              started_at: DateTime.add(ended, -1, :hour),
              ended_at: ended,
              modules: 4
            }
          )
      end

      merged = CodeHeat.window(24)
      assert merged.samples == 2
      assert merged.modules == 4

      assert [
               %{
                 "module" => "TalesForge.AppRole",
                 "function" => "role/1",
                 "calls" => 5,
                 "time_us" => 50
               }
             ] =
               merged.rows

      assert [%{label: "TalesForge.AppRole", calls: 5}] =
               CodeHeat.tiles(merged.rows, level: :module, metric: :calls)
    end

    test "an empty window gives no rows and no tiles" do
      merged = CodeHeat.window(24)
      assert %{samples: 0, modules: 0, rows: [], started_at: nil, ended_at: nil} = merged
      assert CodeHeat.tiles(merged.rows, level: :module, metric: :total) == []

      from = ~U[2026-10-12 00:00:00Z]

      old = %{
        started_at: from,
        ended_at: from,
        modules: 1,
        rows: [
          %{"app" => "a", "module" => "M", "function" => "f/0", "calls" => 1, "time_us" => 1}
        ]
      }

      assert %{samples: 0, rows: []} = CodeHeat.merge([old], from, DateTime.add(from, 24, :hour))
    end
  end

  describe "tiles/2" do
    @rows [
      %{
        "app" => "a",
        "module" => "TalesForge.LLM",
        "function" => "chat/2",
        "calls" => 4,
        "time_us" => 4000
      },
      %{"app" => "a", "module" => "M", "function" => "f/1", "calls" => 1000, "time_us" => 2000},
      %{"app" => "a", "module" => "M", "function" => "g/0", "calls" => 0, "time_us" => 0},
      %{"app" => "a", "module" => "N", "function" => "h/0", "calls" => 10, "time_us" => 10}
    ]

    test "colors by average time and marks AI modules and hot spots" do
      [first | _] = tiles = CodeHeat.tiles(@rows, level: :module, metric: :avg)
      assert first.label == "TalesForge.LLM"
      assert first.value == 1000.0
      assert first.ai
      assert first.hot
      assert first.heat == 1.0
      refute Enum.find(tiles, &(&1.label == "N")).ai
    end

    test "filters by the minimum value" do
      assert ["M"] ==
               @rows
               |> CodeHeat.tiles(level: :module, metric: :calls, min: 100)
               |> Enum.map(& &1.label)

      assert [] == CodeHeat.tiles([], level: :function, metric: :total)
    end

    test "a tile with zero calls is a cold tile" do
      rows = [%{"app" => "a", "module" => "M", "function" => "g/0", "calls" => 0, "time_us" => 0}]

      assert [%{hot: false, heat: +0.0, avg_us: +0.0}] =
               CodeHeat.tiles(rows, level: :function, metric: :calls)
    end
  end

  test "ai_calls/1 counts Jev and LLM calls and their time, with no money" do
    now = DateTime.utc_now()

    for {type, purpose, ms} <- [
          {"jev", "intent", 100},
          {"jev", "intent", 300},
          {"llm", "gm", 2000},
          {"function", "turn.x", 5}
        ] do
      Repo.insert!(%AICall{
        model: "m",
        status: "ok",
        call_type: type,
        purpose: purpose,
        latency_ms: ms,
        cost_micro_usd: 99
      })
    end

    assert [
             %{call_type: "llm", purpose: "gm", calls: 1, total_ms: 2000},
             %{call_type: "jev", purpose: "intent", calls: 2, total_ms: 400, avg_ms: 200.0} = jev
           ] = CodeHeat.ai_calls(DateTime.add(now, -1, :hour))

    refute Map.has_key?(jev, :cost_micro_usd)
  end
end
