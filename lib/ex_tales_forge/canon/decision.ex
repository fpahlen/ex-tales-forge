defmodule TalesForge.Canon.Decision do
  @moduledoc """
  Ecto schema: a founder decision on one difference of one session
  (`canon_decisions`). One row for each session and difference key. A new
  decision on the same key replaces the old one.

  Actions: `session_only` (keep as session-only), `add_to_canon` (record
  the approved change, with `seed_patch` for a pull request) and `error`
  (mark as error). No action changes the session.
  """

  use Ecto.Schema
  import Ecto.Changeset

  @actions ~w(session_only add_to_canon error)

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  @type t :: %__MODULE__{}

  schema "canon_decisions" do
    field :diff_key, :string
    field :action, :string
    field :founder, :string
    field :difference, :map, default: %{}
    field :seed_patch, :string

    belongs_to :game_session, TalesForge.Schemas.GameSession

    timestamps(type: :utc_datetime_usec)
  end

  @doc "The decision actions."
  @spec actions() :: [String.t()]
  def actions, do: @actions

  @doc false
  def changeset(decision, attrs) do
    decision
    |> cast(attrs, [:game_session_id, :diff_key, :action, :founder, :difference, :seed_patch])
    |> validate_required([:game_session_id, :diff_key, :action, :founder])
    |> validate_inclusion(:action, @actions)
    |> validate_format(:founder, ~r/^[^@\s]+@[^@\s]+$/, message: "must be a founder email")
  end
end
