defmodule TalesForge.WorkflowClient do
  @moduledoc """
  The client that the product app uses to send data to Workflow. The
  product app sends only work-log turn events.

  The adapter does the I/O. `TalesForge.WorkflowClient.Local` calls Workflow
  in the same release. `TalesForge.WorkflowClient.Http` posts to the
  Workflow route `POST /internal/workflow/work-log/turns`. The config
  `:ex_tales_forge, TalesForge.WorkflowClient, adapter:` selects the adapter.
  The default is the local adapter.

  `TalesForge.Workers.PushWorkLogTurn` calls this client. The turn queues
  that job in its own transaction, so the turn makes no HTTP call.
  """

  @typedoc "One work-log turn event, with string keys: founder, ref, at, app."
  @type turn_event :: %{required(String.t()) => String.t()}

  @doc "Sends one turn event. `:ok` when Workflow has it."
  @callback push_turn(turn_event()) :: :ok | {:error, term()}

  @doc "The adapter in use."
  @spec adapter() :: module()
  def adapter do
    Application.get_env(:ex_tales_forge, __MODULE__, [])[:adapter] ||
      TalesForge.WorkflowClient.Local
  end

  @doc "Sends one turn event with the adapter in use."
  @spec push_turn(turn_event()) :: :ok | {:error, term()}
  def push_turn(event), do: adapter().push_turn(event)
end
