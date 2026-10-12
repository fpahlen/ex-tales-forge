defmodule TalesForge.Board.Edit do
  @moduledoc """
  One text edit of a card (`board_edits`), append-only. It stores the author,
  the time and the names of the changed fields. The work log reads these rows.
  """
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  @typedoc "A card edit."
  @type t :: %__MODULE__{}

  schema "board_edits" do
    field :author, :string
    field :fields, {:array, :string}, default: []
    belongs_to :idea, TalesForge.Board.Idea
    timestamps(type: :utc_datetime_usec, updated_at: false)
  end

  @doc "Changeset for a new edit."
  @spec changeset(t(), map()) :: Ecto.Changeset.t()
  def changeset(edit, attrs) do
    edit
    |> cast(attrs, [:idea_id, :author, :fields])
    |> validate_required([:idea_id, :author])
  end
end
