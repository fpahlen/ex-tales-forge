defmodule TalesForge.Chat.Thread do
  @moduledoc """
  One thread of the team chat (`TalesForge.Chat`).

  - `kind` is `"subject"` or `"direct"`.
  - A subject thread has a subject and no members. Each founder and each bot
    can read it and post in it.
  - A direct thread is a 1:1 chat. `members` holds the two founder handles,
    sorted. Only those two founders can read it and post in it.
  - `last_message_at` sorts the thread list. A new thread starts with the
    time it was made.
  - The General thread has the key `"general"`. It holds the messages from
    the time before threads.

  The access rules are in `TalesForge.Chat.ThreadRules`.
  """

  use Ecto.Schema
  import Ecto.Changeset

  @type kind :: String.t()
  @type t :: %__MODULE__{
          id: Ecto.UUID.t() | nil,
          key: String.t() | nil,
          subject: String.t() | nil,
          kind: kind() | nil,
          members: [String.t()],
          created_by: String.t() | nil,
          last_message_at: DateTime.t() | nil
        }

  @max_subject 120

  @primary_key {:id, :binary_id, autogenerate: true}
  schema "team_chat_threads" do
    field :key, :string
    field :subject, :string
    field :kind, :string
    field :members, {:array, :string}, default: []
    field :created_by, :string
    field :last_message_at, :utc_datetime_usec
    timestamps(type: :utc_datetime_usec)
  end

  @doc "The longest subject, in characters."
  @spec max_subject() :: pos_integer()
  def max_subject, do: @max_subject

  @doc """
  A changeset for a new thread. `attrs` comes from
  `TalesForge.Chat.ThreadRules`, never from the client as is.
  """
  @spec changeset(t(), map()) :: Ecto.Changeset.t()
  def changeset(thread, attrs) do
    thread
    |> cast(attrs, [:subject, :kind, :members, :created_by, :last_message_at])
    |> update_change(:subject, &String.trim/1)
    |> validate_required([:subject, :kind, :last_message_at], message: "Write a subject first.")
    |> validate_inclusion(:kind, ["subject", "direct"])
    |> validate_length(:subject, max: @max_subject, message: "Write #{@max_subject} characters or fewer.")
    |> unique_constraint(:members, name: :team_chat_threads_direct_members_index)
    |> check_constraint(:members, name: :direct_has_two_members)
  end
end
