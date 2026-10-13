defmodule Workflow.Inbox.Event do
  @moduledoc """
  An event that can put items in an inbox or close them. A plain struct with
  no IO. The edge (`TalesForge.Board.Events`, `TalesForge.Chat`) makes the
  event from the stored change and gives it to `Workflow.Inbox.route/2`.

  Fields:

    * `type`: `:comment` (a comment on a card), `:chat` (a team chat
      message), `:card_closed` (a card moved to Done or the Archive),
      `:pr_waiting` (a PR on a card waits for a founder's OK) or
      `:pr_answered` (a founder approved the PR or asked for changes)
    * `source_id`: the id of the comment or the chat message
    * `idea_id`, `title`: the card and its title, or nil for the chat
    * `author`: a founder email or `bot:<id>`
    * `author_handle`: the founder handle of the author, or nil
    * `mentions`: the founder handles that the body names, without the author
    * `body`: the text of the comment or the message
    * `pr`: for a PR event, `%{number, url, head_sha}`
  """

  @type type :: :comment | :chat | :card_closed | :pr_waiting | :pr_answered

  @type t :: %__MODULE__{
          type: type(),
          source_id: String.t() | nil,
          idea_id: String.t() | nil,
          title: String.t() | nil,
          author: String.t() | nil,
          author_handle: String.t() | nil,
          mentions: [String.t()],
          body: String.t(),
          pr: %{number: pos_integer(), url: String.t() | nil, head_sha: String.t() | nil} | nil
        }

  defstruct type: :comment,
            source_id: nil,
            idea_id: nil,
            title: nil,
            author: nil,
            author_handle: nil,
            mentions: [],
            body: "",
            pr: nil
end
