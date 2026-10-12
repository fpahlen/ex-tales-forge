defmodule TalesForge.Board.GoalVote do
  @moduledoc "One founder's vote on a goal (`board_goal_votes`): +1, or -1 with a reason. One per founder per goal."
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  @typedoc "A goal vote."
  @type t :: %__MODULE__{}

  schema "board_goal_votes" do
    field :founder, :string
    field :value, :integer
    field :reason, :string
    belongs_to :goal, TalesForge.Board.Goal
    timestamps(type: :utc_datetime_usec)
  end

  @doc "Changeset: value must be 1 or -1; a -1 needs a reason, a +1 has none."
  @spec changeset(t(), map()) :: Ecto.Changeset.t()
  def changeset(vote, attrs) do
    vote
    |> cast(attrs, [:goal_id, :founder, :value, :reason])
    |> validate_required([:goal_id, :founder, :value])
    |> validate_inclusion(:value, [1, -1])
    |> then(fn cs ->
      if get_field(cs, :value) == -1,
        do: validate_required(cs, [:reason], message: "is necessary for a downvote"),
        else: put_change(cs, :reason, nil)
    end)
    |> unique_constraint([:goal_id, :founder])
  end
end
