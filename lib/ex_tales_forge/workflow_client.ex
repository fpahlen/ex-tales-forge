defmodule TalesForge.WorkflowClient do
  @moduledoc """
  The client that the product app uses to send data to Workflow. The
  product app sends only work-log turn events.

  The adapter does the I/O. `TalesForge.WorkflowClient.Http` posts to the
  Workflow app's route `POST /internal/workflow/work-log/turns`. The config
  `:ex_tales_forge, :workflow_client, adapter:` selects the adapter
  (`TalesForge.WorkflowClient.Adapter`). The default is the HTTP adapter.

  `TalesForge.Workers.PushWorkLogTurn` calls this client. The turn queues
  that job in its own transaction, so the turn makes no HTTP call.
  """

  alias TalesForge.WorkflowClient.Adapter

  @doc "The adapter in use."
  @spec adapter() :: module()
  def adapter do
    Application.get_env(:ex_tales_forge, :workflow_client, [])[:adapter] ||
      TalesForge.WorkflowClient.Http
  end

  @doc "Sends one turn event with the adapter in use."
  @spec push_turn(Adapter.turn_event()) :: :ok | {:error, term()}
  def push_turn(event), do: adapter().push_turn(event)
end
