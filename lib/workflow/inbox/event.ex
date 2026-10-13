defmodule Workflow.Inbox.Event do
  @moduledoc """
  An event that can put items in an inbox or close them. A plain struct with
  no IO. The edge (`TalesForge.Board.Events`, `TalesForge.Chat`) makes the
  event from the stored change and gives it to `Workflow.Inbox.route/2`.

  Fields:

    * `type`: `:comment` (a comment on a card), `:chat` (a team chat
      message), `:card_closed` (a card moved to Done or the Archive),
      `:check_questions` (a card moved to Founder check with open
      questions), `:question_answered` (a founder answered or deferred a
      question) or `:check_left` (a card left Founder check)
    * `source_id`: the id of the comment or the chat message
    * `idea_id`, `title`: the card and its title, or nil for the chat
    * `author`: a founder email or `bot:<id>`
    * `author_handle`: the founder handle of the author, or nil
    * `mentions`: the founder handles that the body names, without the author
    * `body`: the text of the comment or the message
    * `questions`: the open questions of the card, for `:check_questions`;
      the one question, for `:question_answered`
  """

  @type type ::
          :comment | :chat | :card_closed | :check_questions | :question_answered | :check_left

  @type t :: %__MODULE__{
          type: type(),
          source_id: String.t() | nil,
          idea_id: String.t() | nil,
          title: String.t() | nil,
          author: String.t() | nil,
          author_handle: String.t() | nil,
          mentions: [String.t()],
          body: String.t(),
          questions: [String.t()]
        }

  defstruct type: :comment,
            source_id: nil,
            idea_id: nil,
            title: nil,
            author: nil,
            author_handle: nil,
            mentions: [],
            body: "",
            questions: []
end
