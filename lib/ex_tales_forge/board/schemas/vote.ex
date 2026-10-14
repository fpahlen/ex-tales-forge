defmodule TalesForge.Board.Vote do
  @moduledoc "One founder's vote on an idea (`board_votes`): +1 or -1, one per founder per idea."
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  @typedoc "A vote."
  @type t :: %__MODULE__{}

  @schema_prefix "workflow"

  schema "board_votes" do
    field :founder, :string
    field :value, :integer
    field :reason, :string
    belongs_to :idea, TalesForge.Board.Idea
    timestamps(type: :utc_datetime)
  end

  @doc """
  Changeset: value must be 1 or -1. A -1 needs a reason when
  `opts[:reason_required?]` is true (the default). A -1 without that rule (a
  parked card) can have a reason or none. A +1 has no reason.
  """
  @spec changeset(t(), map(), keyword()) :: Ecto.Changeset.t()
  def changeset(vote, attrs, opts \\ []) do
    vote
    |> cast(attrs, [:idea_id, :founder, :value, :reason])
    |> validate_required([:idea_id, :founder, :value])
    |> validate_inclusion(:value, [1, -1])
    |> then(fn cs ->
      cond do
        get_field(cs, :value) != -1 ->
          put_change(cs, :reason, nil)

        Keyword.get(opts, :reason_required?, true) ->
          validate_required(cs, [:reason], message: "is necessary for a downvote")

        true ->
          cs
      end
    end)
    |> unique_constraint([:idea_id, :founder])
  end
end
