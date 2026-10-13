defmodule TalesForge.WorkflowClient.Local do
  @moduledoc """
  The local adapter of `TalesForge.WorkflowClient`. It gives the turn event
  to Workflow in the same release (`TalesForge.WorkLog.receive_turn/1`). A
  later card replaces it with `TalesForge.WorkflowClient.Http`.
  """

  @behaviour TalesForge.WorkflowClient

  alias TalesForge.WorkLog

  @impl TalesForge.WorkflowClient
  def push_turn(event) do
    case WorkLog.receive_turn(event) do
      {:ok, _} -> :ok
      {:error, reason} -> {:error, reason}
    end
  end
end
