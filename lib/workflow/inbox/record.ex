defmodule Workflow.Inbox.Record do
  @moduledoc """
  One row of `inbox_items`: a stored `Workflow.Inbox.Item` with its state,
  its queue position and its times.

  State is `new`, `done` or `discarded`. Kind is `approve`, `answer` or `ack`.
  """
  use Ecto.Schema

  @primary_key {:id, :binary_id, autogenerate: true}

  @typedoc "An inbox row."
  @type t :: %__MODULE__{}

  @states ~w(new done discarded)

  schema "inbox_items" do
    field :recipient, :string
    field :rule, :string
    field :kind, Ecto.Enum, values: Workflow.Inbox.Item.kinds()
    field :state, :string, default: "new"
    field :position, :integer
    field :source, Ecto.Enum, values: [:comment, :chat, :pr]
    field :source_id, :string
    field :idea_id, :binary_id
    field :url, :string
    field :title, :string
    field :author, :string
    field :body, :string, default: ""
    field :acted_at, :utc_datetime_usec
    timestamps(type: :utc_datetime_usec, inserted_at: :created_at, updated_at: false)
  end

  @doc "The states of an item."
  @spec states() :: [String.t()]
  def states, do: @states
end
