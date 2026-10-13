defmodule TalesForge.CharacterDrafts.StoredDraft do
  @moduledoc """
  One stored character draft (`character_drafts`): the draft of one player
  (`owner`) for one adventure, as an Erlang term.
  """
  use Ecto.Schema

  @primary_key {:id, :binary_id, autogenerate: true}

  @typedoc "A stored draft."
  @type t :: %__MODULE__{}

  schema "character_drafts" do
    field :owner, :string
    field :adventure_id, :string
    field :draft, :binary
    timestamps(type: :utc_datetime_usec)
  end
end
