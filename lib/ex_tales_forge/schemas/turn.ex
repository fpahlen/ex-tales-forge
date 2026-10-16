defmodule TalesForge.Schemas.Turn do
  @moduledoc """
  Ecto schema: one played turn (player action, narrative, mechanical resolution).

  `founder` is the email of the signed-in founder who played the turn. It is
  nil for bot turns (the playtest runner) and for turns before the work log.
  """

  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "turns" do
    field :turn_number, :integer
    field :player_action, :string
    field :narrative, :string
    field :mechanical_resolution, :map, default: %{}
    # Board card 845b6b15: the player character's thought (TalesForge.Characters.Thought).
    field :thought, :map
    field :founder, :string

    belongs_to :game_session, TalesForge.Schemas.GameSession

    timestamps(type: :utc_datetime, updated_at: false)
  end

  def changeset(turn, attrs) do
    turn
    |> cast(attrs, [
      :game_session_id,
      :turn_number,
      :player_action,
      :narrative,
      :mechanical_resolution,
      :founder
    ])
    |> validate_required([:game_session_id, :turn_number, :player_action])
    |> unique_constraint([:game_session_id, :turn_number])
  end
end
