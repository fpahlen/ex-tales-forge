defmodule Workflow.Inbox do
  @moduledoc """
  One triage queue for each person. Pure: each function gets the team config
  (`Workflow.Team`) as its first argument and does no IO. The edge
  (`Workflow.Inbox.Store`) stores the items and runs the actions.

  ## Rules

  Each rule is one entry in `rules/0`. A rule has an id, a kind and the event
  types that it reads. A founder gets the items of a rule only when the team
  config lists the rule id in the `inbox` of that founder
  (`t:Workflow.Team.founder/0`). A founder with no rule ids has no inbox.

  | Rule | Event | Kind | Item |
  |---|---|---|---|
  | `mention` | a comment or a chat message names the founder | answer | one item for each named founder |
  | `thread_message` | a new message in a thread where the founder is a participant | answer | one item for each participant, not the author |
  | `pr_approval` | a PR on a card waits for a founder's OK | approve | one item for each founder with the rule |
  | `founder_check` | a card moves to Founder check with open questions | answer | one item for each open question |
  | `ci_failed` | the `CI` workflow fails on main | ack | one item for each founder with the rule |
  | `deploy_failed` | a `Deploy to ...` workflow fails on main | ack | one item for each founder with the rule |

  The OK on a PR is also the deploy approval: in the normal deploy lane, the
  founder's Approve ships the merge to production after playtest
  (`docs/DEPLOY-FLY.md`). Thus one rule gives the PR and deploy approvals.

  The board sends no `:workflow_failed` event: a failed run on main wakes the
  builder bot, the devops bot (`TalesForge.Board.GitHubEvents`). The two
  rules stay so that a passed run closes the old items.

  The `ci_failed` and `deploy_failed` events have no tag: they name no card
  and no person. A failed CI run on the head of a PR on a card wakes the
  builder (`TalesForge.Board.GitHubEvents`), so it makes no inbox item.

  A message makes at most one item for each founder: a founder that the
  message names gets the `mention` item, not also a `thread_message` item
  (`route/2` keeps the first item of each recipient and source).

  ## Close

  An item closes when its source closes (`closes/2`):

    * The recipient comments on the card of the item.
    * The recipient posts in the team chat (for a chat item).
    * The card moves to Done or to the Archive.
    * A founder answers the PR (Approve or Request changes), or a new head
      of the PR waits. This closes the `pr_approval` items of the card for
      all recipients. A new head then makes a new item.
    * A founder answers or defers a Founder check question. This closes the
      item of that question for all recipients.
    * The card leaves Founder check. This closes its `founder_check` items.
    * The same workflow passes on main. This closes the open items of that
      workflow for all recipients.

  ## Queue

  Each item has a queue position. Skip puts the item at the end of the queue
  (`skip_position/1`). The inbox has no snooze.
  """

  alias Workflow.Inbox.{Event, Item}
  alias Workflow.Team

  @typedoc "A rule: `id` is the id in the team config."
  @type rule :: %{id: String.t(), kind: Item.kind(), events: [Event.type()], about: String.t()}

  @typedoc """
  A close: the items of `recipient` (or of all recipients, `:all`) for the
  card `idea_id`, or for the team chat (`:chat`).
  """
  @type close :: %{
          recipient: String.t() | :all,
          scope:
            {:idea, String.t()}
            | {:idea_rule, String.t(), String.t()}
            | {:source, :question, String.t()}
            | {:workflow, String.t()}
            | :chat
        }

  @typedoc "An action on the current item."
  @type action :: :approve | :answer | :done | :discard | :skip | :next | :prev

  @rules [
    %{
      id: "mention",
      kind: :answer,
      events: [:comment, :chat],
      about: "A comment or a chat message names the founder."
    },
    %{
      id: "thread_message",
      kind: :answer,
      events: [:comment, :chat],
      about: "A new message in a thread where the founder is a participant."
    },
    %{
      id: "pr_approval",
      kind: :approve,
      events: [:pr_waiting],
      about: "A PR on a card waits for a founder's OK. The OK also ships it in the normal lane."
    },
    %{
      id: "founder_check",
      kind: :answer,
      events: [:check_questions],
      about: "A card moves to Founder check with open questions."
    },
    %{
      id: "ci_failed",
      kind: :ack,
      events: [:workflow_failed],
      about: "The CI workflow fails on main."
    },
    %{
      id: "deploy_failed",
      kind: :ack,
      events: [:workflow_failed],
      about: "A deploy workflow fails on main."
    }
  ]

  @doc """
  The rules, in order. Each rule is one entry.

      iex> Workflow.Inbox.rules() |> Enum.map(& &1.id)
      ["mention", "thread_message", "pr_approval", "founder_check", "ci_failed", "deploy_failed"]
  """
  @spec rules() :: [rule()]
  def rules, do: @rules

  @doc """
  The rule ids of the founder with `handle`. Only ids of known rules count.

      iex> Workflow.Inbox.rule_ids(Workflow.Team.example(), "ada")
      ["mention"]
      iex> Workflow.Inbox.rule_ids(Workflow.Team.example(), "lin")
      []
  """
  @spec rule_ids(Team.t(), String.t() | nil) :: [String.t()]
  def rule_ids(%Team{founders: founders}, handle) do
    founders
    |> Enum.find(%{inbox: []}, &(&1.handle == handle))
    |> Map.get(:inbox, [])
    |> Enum.filter(&(&1 in Enum.map(@rules, fn r -> r.id end)))
  end

  @doc """
  True when the founder with `handle` has at least one rule.

      iex> team = Workflow.Team.example()
      iex> {Workflow.Inbox.has_inbox?(team, "ada"), Workflow.Inbox.has_inbox?(team, "lin"), Workflow.Inbox.has_inbox?(team, nil)}
      {true, false, false}
  """
  @spec has_inbox?(Team.t(), String.t() | nil) :: boolean()
  def has_inbox?(%Team{} = team, handle), do: rule_ids(team, handle) != []

  @doc """
  The items that `event` puts in the inboxes, one for each recipient and
  source at most.

      iex> team = Workflow.Team.example()
      iex> event = %Workflow.Inbox.Event{type: :comment, source_id: "c1", idea_id: "i1", mentions: ["ada", "lin"], body: "@ada @lin look"}
      iex> Workflow.Inbox.route(team, event) |> Enum.map(&{&1.recipient, &1.kind, &1.url})
      [{"ada", :answer, "/team#idea-i1"}]
  """
  @spec route(Team.t(), Event.t()) :: [Item.t()]
  def route(%Team{} = team, %Event{} = event) do
    for rule <- @rules,
        event.type in rule.events,
        founder <- team.founders,
        rule.id in rule_ids(team, founder.handle),
        rule_match?(rule, event, founder.handle),
        item <- items(rule, event, founder.handle) do
      item
    end
    |> Enum.uniq_by(&{&1.recipient, &1.source, &1.source_id})
  end

  # One clause for each rule id.
  defp rule_match?(%{id: "mention"}, %Event{mentions: mentions, author_handle: author}, handle),
    do: handle in mentions and handle != author

  defp rule_match?(
         %{id: "thread_message"},
         %Event{participants: participants, author_handle: author},
         handle
       ),
       do: handle in participants and handle != author

  defp rule_match?(%{id: "ci_failed"}, %Event{workflow: workflow}, _handle),
    do: workflow == "CI"

  defp rule_match?(%{id: "deploy_failed"}, %Event{workflow: workflow}, _handle),
    do: is_binary(workflow) and String.starts_with?(workflow, "Deploy")

  defp rule_match?(%{id: "pr_approval"}, %Event{pr: %{number: n}, idea_id: id}, _handle),
    do: is_integer(n) and is_binary(id)

  defp rule_match?(%{id: "founder_check"}, %Event{idea_id: id}, _handle), do: is_binary(id)

  # One item for each open question; one item for the other rules.
  defp items(%{id: "founder_check"} = rule, %Event{} = event, handle) do
    for question <- event.questions do
      %{
        item(rule, event, handle)
        | source: :question,
          source_id: question_id(event.idea_id, question),
          body: question
      }
    end
  end

  defp items(rule, event, handle), do: [item(rule, event, handle)]

  @doc """
  The source id of a Founder check question on a card.

      iex> Workflow.Inbox.question_id("i1", "How big?") == Workflow.Inbox.question_id("i1", "How big?")
      true
  """
  @spec question_id(String.t(), String.t()) :: String.t()
  def question_id(idea_id, question),
    do:
      "q-#{idea_id}-#{:crypto.hash(:sha256, question) |> Base.encode16(case: :lower) |> binary_part(0, 16)}"

  defp item(rule, event, handle) do
    %Item{
      recipient: handle,
      rule: rule.id,
      kind: rule.kind,
      source: source(event),
      source_id: source_id(event),
      idea_id: event.idea_id,
      title: event.title || event.workflow,
      author: event.author,
      body: event.body,
      url: url(event)
    }
  end

  defp source(%Event{type: :pr_waiting}), do: :pr
  defp source(%Event{type: type}) when type in [:workflow_failed, :workflow_passed], do: :github
  defp source(%Event{type: type}), do: type

  # One approve item for each PR head: a new head that waits again makes a new item.
  defp source_id(%Event{type: :pr_waiting, pr: pr}), do: "pr-#{pr.number}-#{pr.head_sha}"
  defp source_id(%Event{source_id: id}), do: id

  @doc """
  The source link of an event: the card on `/team`, or the team chat.

      iex> Workflow.Inbox.url(%Workflow.Inbox.Event{type: :chat})
      "/team#chat"
  """
  @spec url(Event.t()) :: String.t()
  def url(%Event{url: url}) when is_binary(url), do: url
  def url(%Event{type: :chat}), do: "/team#chat"
  def url(%Event{idea_id: id}) when is_binary(id), do: "/team#idea-" <> id
  def url(%Event{}), do: "/team"

  @doc """
  The items that `event` closes.

      iex> team = Workflow.Team.example()
      iex> Workflow.Inbox.closes(team, %Workflow.Inbox.Event{type: :comment, idea_id: "i1", author_handle: "ada"})
      [%{recipient: "ada", scope: {:idea, "i1"}}]
      iex> Workflow.Inbox.closes(team, %Workflow.Inbox.Event{type: :card_closed, idea_id: "i1"})
      [%{recipient: :all, scope: {:idea, "i1"}}]
      iex> Workflow.Inbox.closes(team, %Workflow.Inbox.Event{type: :pr_answered, idea_id: "i1"})
      [%{recipient: :all, scope: {:idea_rule, "i1", "pr_approval"}}]
      iex> Workflow.Inbox.closes(team, %Workflow.Inbox.Event{type: :chat, author_handle: "lin"})
      []
  """
  @spec closes(Team.t(), Event.t()) :: [close()]
  def closes(_team, %Event{type: :card_closed, idea_id: id}) when is_binary(id),
    do: [%{recipient: :all, scope: {:idea, id}}]

  def closes(_team, %Event{type: type, idea_id: id})
      when type in [:pr_waiting, :pr_answered] and is_binary(id),
      do: [%{recipient: :all, scope: {:idea_rule, id, "pr_approval"}}]

  def closes(_team, %Event{type: :question_answered, idea_id: id, questions: questions})
      when is_binary(id),
      do:
        for(
          q <- questions,
          do: %{recipient: :all, scope: {:source, :question, question_id(id, q)}}
        )

  def closes(_team, %Event{type: :check_left, idea_id: id}) when is_binary(id),
    do: [%{recipient: :all, scope: {:idea_rule, id, "founder_check"}}]

  def closes(_team, %Event{type: :workflow_passed, workflow: workflow}) when is_binary(workflow),
    do: [%{recipient: :all, scope: {:workflow, workflow}}]

  def closes(team, %Event{type: type, author_handle: handle} = event)
      when type in [:comment, :chat] and is_binary(handle) do
    if has_inbox?(team, handle), do: [%{recipient: handle, scope: scope(event)}], else: []
  end

  def closes(_team, %Event{}), do: []

  defp scope(%Event{type: :chat}), do: :chat
  defp scope(%Event{idea_id: id}), do: {:idea, id}

  @doc """
  The queue position for a skipped item: after the last position.

      iex> Workflow.Inbox.skip_position([1, 4, 2])
      5
      iex> Workflow.Inbox.skip_position([])
      1
  """
  @spec skip_position([integer()]) :: integer()
  def skip_position(positions), do: Enum.max(positions, fn -> 0 end) + 1

  @doc """
  The action of a key on an item of `kind`. `a` approves an approve item and
  acknowledges an ack item. `Enter` gives the focus to the answer field.

      iex> Workflow.Inbox.key_action("a", :approve)
      :approve
      iex> Workflow.Inbox.key_action("a", :answer)
      nil
      iex> Enum.map(~w(Enter d e s j k), &Workflow.Inbox.key_action(&1, :answer))
      [:answer, :discard, :done, :skip, :next, :prev]
  """
  @spec key_action(String.t(), Item.kind()) :: action() | nil
  def key_action("a", :approve), do: :approve
  def key_action("a", :ack), do: :done
  def key_action("Enter", :answer), do: :answer
  def key_action("d", _kind), do: :discard
  def key_action("e", _kind), do: :done
  def key_action("s", _kind), do: :skip
  def key_action("j", _kind), do: :next
  def key_action("k", _kind), do: :prev
  def key_action(_key, _kind), do: nil

  @doc """
  The index after a `:next` or `:prev` move in a queue of `count` items. The
  index stays in the queue.

      iex> {Workflow.Inbox.step(0, :next, 3), Workflow.Inbox.step(2, :next, 3), Workflow.Inbox.step(0, :prev, 3)}
      {1, 2, 0}
  """
  @spec step(non_neg_integer(), :next | :prev, non_neg_integer()) :: non_neg_integer()
  def step(_index, _dir, count) when count < 1, do: 0
  def step(index, :next, count), do: min(index + 1, count - 1)
  def step(index, :prev, _count), do: max(index - 1, 0)

  @doc """
  The state of an item after a final action.

      iex> {Workflow.Inbox.state_after(:done), Workflow.Inbox.state_after(:discard), Workflow.Inbox.state_after(:approve)}
      {"done", "discarded", "done"}
  """
  @spec state_after(:approve | :answer | :done | :discard) :: String.t()
  def state_after(:discard), do: "discarded"
  def state_after(action) when action in [:approve, :answer, :done], do: "done"
end
