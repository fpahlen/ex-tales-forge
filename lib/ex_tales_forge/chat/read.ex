defmodule TalesForge.Chat.Read do
  @moduledoc "When a founder (by handle) last opened a thread of the team chat."

  use Ecto.Schema

  @type t :: %__MODULE__{}

  @primary_key false
  @schema_prefix "workflow"
  schema "team_chat_reads" do
    field :handle, :string, primary_key: true
    field :thread_id, :binary_id, primary_key: true
    field :read_at, :utc_datetime_usec
  end
end
