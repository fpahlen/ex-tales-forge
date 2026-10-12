defmodule TalesForge.WorkLog.Event do
  @moduledoc """
  One founder action for the work log (`work_log_events`), append-only.

  - `founder`: the founder email.
  - `kind`: the action type (`TalesForge.WorkLog.kinds/0`).
  - `app`: the app where the action occurred (`production`, `playtest` or `local`).
  - `ref`: the id of the source row (the comment, the move, the message, the
    edit or the turn).
  - `at`: the time of the action.
  """
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}

  @typedoc "An activity event."
  @type t :: %__MODULE__{}

  schema "work_log_events" do
    field :founder, :string
    field :kind, :string
    field :app, :string
    field :ref, :string
    field :at, :utc_datetime_usec
    timestamps(type: :utc_datetime_usec, updated_at: false)
  end

  @doc "Changeset for a new event."
  @spec changeset(t(), map()) :: Ecto.Changeset.t()
  def changeset(event, attrs) do
    event
    |> cast(attrs, [:founder, :kind, :app, :ref, :at])
    |> validate_required([:founder, :kind, :app, :ref, :at])
    |> validate_inclusion(:kind, TalesForge.WorkLog.kinds())
    |> validate_inclusion(:app, ~w(production playtest local))
    |> unique_constraint([:app, :kind, :ref])
  end
end
