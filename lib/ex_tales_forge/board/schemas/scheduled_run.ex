defmodule TalesForge.Board.ScheduledRun do
  @moduledoc """
  One run of a scheduled job (`scheduled_runs`). `job_id` is the id of the
  job in the team config (`Workflow.Team` `jobs`). `status` is `"open"` while
  the run works, then `"ok"` or `"failed"`. A bot run that sends no report
  before `deadline_at` gets `"no_report"`. All times are in UTC.
  """
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}

  @typedoc "A scheduled run."
  @type t :: %__MODULE__{}

  @statuses ~w(open ok failed no_report)

  @schema_prefix "workflow"

  schema "scheduled_runs" do
    field :job_id, :string
    field :owner, :string
    field :status, :string, default: "open"
    field :detail, :string
    field :started_at, :utc_datetime_usec
    field :finished_at, :utc_datetime_usec
    field :deadline_at, :utc_datetime_usec
    timestamps(type: :utc_datetime_usec)
  end

  @doc "The run statuses."
  @spec statuses() :: [String.t()]
  def statuses, do: @statuses

  @doc "Changeset for a new run."
  @spec changeset(t(), map()) :: Ecto.Changeset.t()
  def changeset(run, attrs) do
    run
    |> cast(attrs, [:job_id, :owner, :status, :detail, :started_at, :finished_at, :deadline_at])
    |> validate_required([:job_id, :owner, :status, :started_at])
    |> validate_inclusion(:status, @statuses)
  end
end
