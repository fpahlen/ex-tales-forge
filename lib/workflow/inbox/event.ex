defmodule Workflow.Inbox.Event do
  @moduledoc """
  An event that can put items in an inbox or close them. A plain struct with
  no IO. The edge (`TalesForge.Board.Events`, `TalesForge.Chat`) makes the
  event from the stored change and gives it to `Workflow.Inbox.route/2`.

  Fields:

    * `type`: `:comment` (a comment on a card), `:chat` (a team chat
      message), `:card_closed` (a card moved to Done or the Archive),
      `:pr_waiting` (a PR on a card waits for a founder's OK),
      `:pr_answered` (a founder approved the PR or asked for changes),
      `:check_questions` (a card moved to Founder check with open
      questions), `:question_answered` (a founder answered or deferred a
      question), `:check_left` (a card left Founder check), or
      `:workflow_failed` or `:workflow_passed` (a GitHub Actions run on
      main ended; no card and no person is tagged)
    * `source_id`: the id of the comment or the chat message
    * `idea_id`, `title`: the card and its title, or nil for the chat
    * `author`: a founder email or `bot:<id>`
    * `author_handle`: the founder handle of the author, or nil
    * `mentions`: the founder handles that the body names, without the author
    * `body`: the text of the comment or the message
    * `pr`: for a PR event, `%{number, url, head_sha}`
    * `questions`: the open questions of the card, for `:check_questions`;
      the one question, for `:question_answered`
    * `workflow`: for a run, the workflow name (`"CI"`, `"Deploy to playtest"`)
    * `sha`: for a run, the head commit
    * `url`: for a run, the link to the commit on GitHub
  """

  @type type ::
          :comment
          | :chat
          | :card_closed
          | :pr_waiting
          | :pr_answered
          | :check_questions
          | :question_answered
          | :check_left
          | :workflow_failed
          | :workflow_passed

  @type t :: %__MODULE__{
          type: type(),
          source_id: String.t() | nil,
          idea_id: String.t() | nil,
          title: String.t() | nil,
          author: String.t() | nil,
          author_handle: String.t() | nil,
          mentions: [String.t()],
          body: String.t(),
          pr: %{number: pos_integer(), url: String.t() | nil, head_sha: String.t() | nil} | nil,
          questions: [String.t()],
          workflow: String.t() | nil,
          sha: String.t() | nil,
          url: String.t() | nil
        }

  defstruct type: :comment,
            source_id: nil,
            idea_id: nil,
            title: nil,
            author: nil,
            author_handle: nil,
            mentions: [],
            body: "",
            pr: nil,
            questions: [],
            workflow: nil,
            sha: nil,
            url: nil
end
