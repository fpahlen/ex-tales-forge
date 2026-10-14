defmodule TalesForge.PrFeed.Reconcile do
  @moduledoc """
  The backup for missed webhooks: Oban cron runs this job every 30 minutes
  (the job `pr_feed_backup` in the team config). It tells the poller on each machine
  (`TalesForge.PrFeed.Poller`) to read GitHub in full again and to build the
  feed from that read. Each run gets a row in `scheduled_runs`
  (`TalesForge.Board.Schedule.track/2`).
  """
  use Oban.Worker, queue: :default, max_attempts: 1

  alias TalesForge.Board.Schedule

  @topic "pr_feed:reconcile"

  @doc "The PubSub topic of the reconcile signal."
  @spec topic() :: String.t()
  def topic, do: @topic

  @impl Oban.Worker
  def perform(%Oban.Job{args: args}) do
    Schedule.track(Map.get(args, "job_id", "pr_feed_backup"), fn ->
      Phoenix.PubSub.broadcast(TalesForge.PubSub, @topic, :reconcile)
    end)
  end
end
