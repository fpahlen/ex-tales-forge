defmodule Workflow.Push.Worker do
  @moduledoc """
  Sends the web push of one inbox item (`Workflow.Push.deliver/1`). Queue
  `:default` of the Workflow Oban instance. A push service error makes Oban
  retry, up to 5 times. A closed item sends nothing.
  """

  use Oban.Worker, queue: :default, max_attempts: 5

  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"item_id" => id}}) do
    results = Workflow.Push.deliver(id)

    case Enum.filter(results, &match?({:error, _}, &1)) do
      [] -> :ok
      [error | _] -> error
    end
  end
end
