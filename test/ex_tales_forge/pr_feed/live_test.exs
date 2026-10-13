defmodule TalesForge.PrFeed.LiveTest do
  @moduledoc "The feed model changes event by event, with no full rebuild."
  use ExUnit.Case, async: true

  alias TalesForge.GitEvents.GitEvent
  alias TalesForge.PrFeed
  alias TalesForge.PrFeed.Live

  @now ~U[2026-10-13 10:00:00Z]

  defp pr(n, state, attrs \\ %{}) do
    Map.merge(
      %{
        number: n,
        title: "PR #{n}",
        author: "bobby",
        url: nil,
        state: state,
        draft: false,
        head_sha: "head#{n}aaaa",
        merge_sha: nil,
        created_at: ~U[2026-10-12 08:00:00Z],
        merged_at: nil,
        closed_at: nil,
        updated_at: ~U[2026-10-12 08:00:00Z]
      },
      attrs
    )
  end

  defp model do
    merged =
      pr(1, :merged, %{merge_sha: "m1m1m1m1", merged_at: ~U[2026-10-13 07:00:00Z]})

    commits = [%{sha: "m1m1m1m1", at: ~U[2026-10-13 07:00:00Z]}]

    inputs = %{
      pulls: [merged, pr(2, :open)],
      ci: %{},
      main: ["m1m1m1m1"],
      commits: commits,
      running: %{playtest: "m1m1m1m1", production: "m1m1m1m1"}
    }

    Live.new(inputs, @now)
  end

  defp event(attrs), do: struct!(GitEvent, Map.merge(%{repo: "whyse-ab/ex-tales-forge"}, attrs))

  test "a merged pull request updates its item, the counters and the pace" do
    model = model()
    assert model.snapshot.merged_today == 1

    merged = pr(2, :merged, %{merge_sha: "m2m2m2m2", merged_at: ~U[2026-10-13 09:00:00Z]})
    {:changed, model} = Live.apply(model, event(%{type: :pull_request, pull: merged}), @now)

    assert [%{number: 2, state: :merged}, %{number: 1}] = model.snapshot.items
    assert model.snapshot.merged_today == 2
    assert model.snapshot.pace.prs_merged == 2
    assert model.snapshot.pace.prs_open == 0
    # A merge commit that main does not list yet counts as included.
    assert hd(model.snapshot.items).deployed.playtest == :deployed

    # The push to main and a new running commit: pending, then deployed.
    push = event(%{type: :push, branch: "main", commits: [%{sha: "m2m2m2m2", at: @now}]})
    {:changed, model} = Live.apply(model, push, @now)
    assert hd(model.snapshot.items).deployed.playtest == :pending
    assert model.snapshot.pace.commits == 2

    model = Live.put_running(model, %{playtest: "m2m2m2m2", production: "m1m1m1m1"}, @now)
    assert hd(model.snapshot.items).deployed == %{playtest: :deployed, production: :pending}
  end

  test "the same result as a full build from the same inputs" do
    model = model()
    new_pr = pr(3, :open, %{created_at: ~U[2026-10-13 09:30:00Z]})
    {:changed, model} = Live.apply(model, event(%{type: :pull_request, pull: new_pr}), @now)

    full =
      PrFeed.build(
        %{
          pulls: Map.values(model.pulls),
          ci: %{},
          main: ["m1m1m1m1"],
          commits: [%{sha: "m1m1m1m1", at: ~U[2026-10-13 07:00:00Z]}],
          running: model.running
        },
        @now
      )

    assert model.snapshot.items == full.items
    assert model.snapshot.pace.prs_by_day == full.pace.prs_by_day
    assert model.snapshot.merged_week == full.merged_week
  end

  test "a CI run changes the badge of the open pull request with that head" do
    run = event(%{type: :workflow_run, workflow: "CI", sha: "head2aaaa", ci: :failed})
    {:changed, model} = Live.apply(model(), run, @now)
    assert Enum.find(model.snapshot.items, &(&1.number == 2)).ci == :failed
  end

  test "a finished deploy asks for the running commits; other events change nothing" do
    deploy =
      event(%{type: :workflow_run, workflow: "Deploy to playtest", action: "completed"})

    assert {:refresh_running, _} = Live.apply(model(), deploy, @now)
    assert Live.apply(model(), event(%{type: :check_suite, sha: "x"}), @now) == :unchanged
  end
end
