defmodule TalesForge.PrFeed.Reconcile do
  @moduledoc """
  The backup for missed webhooks: Oban cron runs this job every 30 minutes
  (`config/config.exs`). It tells the poller on each machine
  (`TalesForge.PrFeed.Poller`) to read GitHub in full again and to build the
  feed from that read.
  """
  use Oban.Worker, queue: :default, max_attempts: 1

  @topic "pr_feed:reconcile"

  @doc "The PubSub topic of the reconcile signal."
  @spec topic() :: String.t()
  def topic, do: @topic

  @impl Oban.Worker
  def perform(%Oban.Job{}) do
    Phoenix.PubSub.broadcast(TalesForge.PubSub, @topic, :reconcile)
  end
end
