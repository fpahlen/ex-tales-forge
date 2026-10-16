defmodule TalesForge.Schemas.CharacterMemory do
  @moduledoc """
  Ecto schema: one character's own, personality-filtered view of an event.
  The event itself lives once in the shared `session_events` table; several
  characters can remember it differently (felt, salience, secret).
  """

  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id
  @kinds ~w(memory promise reaction fact)
  @tiers ~w(working short long faded)

  @type t :: %__MODULE__{}

  schema "character_memories" do
    field :kind, :string
    field :text, :string
    field :felt, :string
    field :salience, :float, default: 0.5
    field :secret, :boolean, default: false
    field :tick, :integer
    # Board card fc3c9371: the tier, the ids the memory is about (people,
    # places, items) and the weight from the character's interests.
    field :tier, :string, default: "short"
    field :about, {:array, :string}, default: []
    field :weight, :float, default: 1.0
    # Board card 845b6b15: the character's belief from compression; it can be wrong.
    field :belief, :string

    belongs_to :character, TalesForge.Schemas.Character
    belongs_to :session_event, TalesForge.Schemas.SessionEvent

    timestamps(type: :utc_datetime, updated_at: false)
  end

  @doc "The allowed memory kinds."
  def kinds, do: @kinds

  @doc "The allowed memory tiers."
  def tiers, do: @tiers

  def changeset(memory, attrs) do
    memory
    |> cast(attrs, [
      :character_id,
      :session_event_id,
      :kind,
      :text,
      :felt,
      :salience,
      :secret,
      :tick,
      :tier,
      :about,
      :weight,
      :belief
    ])
    |> validate_required([:character_id, :kind, :text])
    |> validate_inclusion(:kind, @kinds)
    |> validate_inclusion(:tier, @tiers)
    |> validate_number(:weight, greater_than_or_equal_to: 0.0)
    |> validate_number(:salience, greater_than_or_equal_to: 0.0, less_than_or_equal_to: 1.0)
    |> assoc_constraint(:character)
    |> check_constraint(:kind, name: :character_memories_kind_check)
    |> check_constraint(:tier, name: :character_memories_tier_check)
  end
end
