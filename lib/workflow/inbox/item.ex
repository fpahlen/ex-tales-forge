defmodule Workflow.Inbox.Item do
  @moduledoc """
  One item in the inbox of one person. `Workflow.Inbox.route/2` makes the
  items. A plain struct with no IO. The edge stores each item as one row of
  `inbox_items` (`Workflow.Inbox.Record`).

  Fields:

    * `recipient`: the founder handle that gets the item
    * `rule`: the id of the rule that made the item
    * `kind`: `:approve`, `:answer` or `:ack`
    * `source`: `:comment` or `:chat`
    * `source_id`, `idea_id`, `title`, `author`, `body`: from the event
    * `url`: the source link
  """

  @type kind :: :approve | :answer | :ack

  @type t :: %__MODULE__{
          recipient: String.t(),
          rule: String.t(),
          kind: kind(),
          source: :comment | :chat,
          source_id: String.t() | nil,
          idea_id: String.t() | nil,
          title: String.t() | nil,
          author: String.t() | nil,
          body: String.t(),
          url: String.t()
        }

  defstruct recipient: nil,
            rule: nil,
            kind: :ack,
            source: :comment,
            source_id: nil,
            idea_id: nil,
            title: nil,
            author: nil,
            body: "",
            url: "/team"

  @doc "The item kinds."
  @spec kinds() :: [kind()]
  def kinds, do: [:approve, :answer, :ack]
end
