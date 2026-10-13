defmodule TalesForge.WorkLog.Entry do
  @moduledoc """
  One manual work log entry (`work_log_entries`). A founder adds hours, a
  date and a reason. Use it for work outside the app and for the hours from
  the old spreadsheet (reason "Imported from spreadsheet", the original date).

  The changeset takes `hours` (for example `1.5`) and stores whole minutes.
  """
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}

  @typedoc "A manual entry."
  @type t :: %__MODULE__{}

  @max_minutes 24 * 60

  @schema_prefix "workflow"

  schema "work_log_entries" do
    field :founder, :string
    field :date, :date
    field :minutes, :integer
    field :reason, :string
    field :added_by, :string
    field :hours, :float, virtual: true
    timestamps(type: :utc_datetime_usec, updated_at: false)
  end

  @doc "Changeset for a new entry: founder, date, hours, reason and added_by."
  @spec changeset(t(), map()) :: Ecto.Changeset.t()
  def changeset(entry, attrs) do
    entry
    |> cast(attrs, [:founder, :date, :hours, :reason, :added_by])
    |> update_change(:founder, &(&1 |> String.trim() |> String.downcase()))
    |> update_change(:reason, &String.trim/1)
    |> validate_required([:founder, :date, :hours, :reason, :added_by])
    |> validate_format(:founder, ~r/^[^@\s]+@[^@\s]+$/, message: "must be a founder email")
    |> validate_number(:hours, greater_than: 0, less_than_or_equal_to: 24)
    |> validate_length(:reason, min: 3, max: 500)
    |> put_minutes()
  end

  defp put_minutes(%{valid?: true} = cs) do
    minutes = cs |> get_change(:hours) |> Kernel.*(60) |> round() |> min(@max_minutes)
    put_change(cs, :minutes, minutes)
  end

  defp put_minutes(cs), do: cs
end
