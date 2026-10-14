defmodule TalesForge.PrFeed.PerfTest do
  @moduledoc "The heat map fixes: one sha lookup per build, one day per UTC hour, slower polls."
  use ExUnit.Case, async: true

  alias TalesForge.PrFeed.Deploys
  alias TalesForge.PrFeed.Pace

  describe "Deploys.index/1" do
    test "gives the same status as the list for full and short shas" do
      main = for n <- 300..1//-1, do: String.duplicate(Integer.to_string(n, 16), 10)
      index = Deploys.index(main)

      for merge <- Enum.take_every(main, 37) ++ ["0000000", "short"],
          running <- [Enum.at(main, 5), String.slice(Enum.at(main, 150), 0, 7), nil, "x"] do
        assert Deploys.status(merge, index, running) == Deploys.status(merge, main, running)
      end
    end

    test "matches shas without regard to case" do
      index = Deploys.index(["ABCDEF12", "abcdef00"])
      assert Deploys.status("abcdef00", index, "AbCdEf12") == :deployed
      assert Deploys.status("abcdef12", index, "ABCDEF00") == :pending
    end
  end

  describe "Pace.build/3" do
    test "counts each entry on its Stockholm day across the daylight saving change" do
      # 2026-10-25 01:00 UTC: Stockholm goes from UTC+2 to UTC+1.
      at = [
        ~U[2026-10-24 21:59:59Z],
        ~U[2026-10-24 22:00:00Z],
        ~U[2026-10-25 22:59:59Z],
        ~U[2026-10-25 23:00:00Z],
        ~U[2026-10-25 23:30:00Z]
      ]

      commits = Enum.map(at, &%{sha: "s", at: &1})
      pace = Pace.build([], commits, ~U[2026-10-26 12:00:00Z])

      assert pace.commits_by_day == [
               %{"date" => "2026-10-24", "count" => 1},
               %{"date" => "2026-10-25", "count" => 2},
               %{"date" => "2026-10-26", "count" => 2}
             ]

      expected = at |> Enum.map(&Pace.day/1) |> Enum.frequencies()
      assert Map.new(pace.commits_by_day, &{&1["date"], &1["count"]}) == expected
    end
  end

  test "the feed has no poll interval and reconciles every 30 minutes" do
    refute Keyword.has_key?(
             Application.fetch_env!(:ex_tales_forge, TalesForge.PrFeed),
             :interval_ms
           )

    config = Config.Reader.read!("config/config.exs", env: :prod)

    {_, cron} =
      Enum.find(
        config[:ex_tales_forge][TalesForge.Workflow.Oban][:plugins],
        &match?({Oban.Plugins.Cron, _}, &1)
      )

    assert {"*/30 * * * *", TalesForge.PrFeed.Reconcile} in cron[:crontab]
  end

  test "Oban stages scheduled jobs every 30 seconds" do
    config = Config.Reader.read!("config/config.exs", env: :prod)
    assert config[:ex_tales_forge][Oban][:stage_interval] == 30_000
  end
end
