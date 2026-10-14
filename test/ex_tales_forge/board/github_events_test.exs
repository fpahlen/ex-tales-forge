defmodule TalesForge.Board.GitHubEventsTest do
  @moduledoc "What each GitHub event means for the board."
  use ExUnit.Case, async: true

  alias TalesForge.Board.GitHubEvents
  alias TalesForge.GitEvents.GitEvent

  doctest GitHubEvents

  defp run(workflow, ci),
    do: %GitEvent{
      type: :workflow_run,
      repo: "whyse-ab/ex-tales-forge",
      action: "completed",
      workflow: workflow,
      ci: ci,
      sha: "abc1234",
      branch: "main",
      actor: "fpahlen"
    }

  describe "a failed run on main" do
    test "CI wakes the builder bot and makes no inbox item" do
      steps = GitHubEvents.plan(run("CI", :failed))
      assert [{:wake_sha, :ci_failed, "abc1234"}, {:wake_run, :run_failed, r}] = steps
      assert r["workflow"] == "CI"
      assert r["actor"] == "fpahlen"
      refute Enum.any?(steps, &match?({:inbox, _}, &1))
    end

    test "a deploy workflow wakes the builder bot and makes no inbox item" do
      assert [{:wake_run, :run_failed, %{"workflow" => "Deploy to production"}}] =
               GitHubEvents.plan(run("Deploy to production", :failed))
    end
  end

  test "a passed run on main gives the inbox a close event" do
    assert [{:inbox, %{type: :workflow_passed}}] = GitHubEvents.plan(run("CI", :passed))
  end
end
