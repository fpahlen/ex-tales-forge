defmodule TalesForge.Board.Goal do
  @moduledoc """
  A goal on the founders' idea board (`board_goals`): a short title, the
  outcome line that tells when it is reached, an optional target date (the
  last day of the target month for a month target) with its label, and a
  sort position. Founders vote on goals (`TalesForge.Board.GoalVote`). A card
  has zero or one goal (`board_ideas.goal_id`).
  """
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  @typedoc "A goal."
  @type t :: %__MODULE__{}

  @schema_prefix "workflow"

  schema "board_goals" do
    field :key, :string
    field :title, :string
    field :outcome, :string, default: ""
    field :target_date, :date
    field :target_label, :string
    field :sort, :integer, default: 0
    has_many :votes, TalesForge.Board.GoalVote
    timestamps(type: :utc_datetime_usec)
  end

  @doc "Changeset: key and title are necessary; the target date can be empty."
  @spec changeset(t(), map()) :: Ecto.Changeset.t()
  def changeset(goal, attrs) do
    goal
    |> cast(attrs, [:key, :title, :outcome, :target_date, :target_label, :sort])
    |> validate_required([:key, :title])
    |> validate_length(:title, min: 3, max: 160)
    |> unique_constraint(:key)
  end
end
