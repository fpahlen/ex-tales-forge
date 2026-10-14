defmodule TalesForge.Board.Deletion do
  @moduledoc """
  The audit record of one hard delete from the Archive (`board_deletions`),
  append-only: which card (id and title), who deleted it, the archive
  reason and how many images went with it. Written by
  `TalesForge.Board.delete_archived/3`.
  """
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  @typedoc "A deletion."
  @type t :: %__MODULE__{}

  @schema_prefix "workflow"

  schema "board_deletions" do
    field :idea_id, :binary_id
    field :title, :string
    field :deleted_by, :string
    field :archive_reason, :string
    field :image_count, :integer, default: 0
    timestamps(type: :utc_datetime_usec, updated_at: false)
  end

  @doc "Changeset for a new deletion record."
  @spec changeset(t(), map()) :: Ecto.Changeset.t()
  def changeset(deletion, attrs) do
    deletion
    |> cast(attrs, [:idea_id, :title, :deleted_by, :archive_reason, :image_count])
    |> validate_required([:idea_id, :title, :deleted_by])
  end
end
