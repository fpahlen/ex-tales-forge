defmodule TalesForge.Workers.PushWorkLogTurn do
  @moduledoc """
  Sends one work-log turn event to Workflow (`TalesForge.WorkflowClient`).

  `TalesForge.Game.TurnProcessor` queues this job in the turn transaction,
  only for a turn that a founder played. The turn makes no HTTP call. A
  failed send fails the job, and Oban tries again (up to 20 attempts).
  Workflow stores the same event only one time, so a retry is safe.
  """

  use Oban.Worker, queue: :default, max_attempts: 20

  alias TalesForge.AppRole
  alias TalesForge.WorkflowClient

  @doc """
  The job for the turn `turn` (a map with `id`, `founder` and
  `inserted_at`), or nil when no founder played it.
  """
  @spec job(map()) :: Oban.Job.changeset() | nil
  def job(%{founder: founder} = turn) when is_binary(founder) and founder != "" do
    new(%{
      "founder" => founder,
      "ref" => to_string(turn.id),
      "at" => turn.inserted_at |> to_utc() |> DateTime.to_iso8601(),
      "app" => Atom.to_string(AppRole.role())
    })
  end

  def job(_turn), do: nil

  @impl Oban.Worker
  def perform(%Oban.Job{args: args}) do
    case WorkflowClient.push_turn(args) do
      :ok -> :ok
      {:error, :invalid} -> {:cancel, :invalid}
      {:error, reason} -> {:error, reason}
    end
  end

  defp to_utc(%DateTime{} = at), do: at
  defp to_utc(%NaiveDateTime{} = at), do: DateTime.from_naive!(at, "Etc/UTC")
end
