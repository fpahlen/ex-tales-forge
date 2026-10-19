defmodule TalesForge.WorkflowClient.Adapter do
  @moduledoc """
  The behaviour of a `TalesForge.WorkflowClient` adapter
  (`TalesForge.WorkflowClient.Http`). A leaf: the adapters and the client
  both depend on it.
  """

  @typedoc "One work-log turn event, with string keys: founder, ref, at, app."
  @type turn_event :: %{required(String.t()) => String.t()}

  @doc "Sends one turn event. `:ok` when Workflow has it."
  @callback push_turn(turn_event()) :: :ok | {:error, term()}
end
