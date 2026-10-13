defmodule TalesForge.Board.Events do
  @moduledoc """
  What a board change sets off, added to the same `Ecto.Multi` as the change
  (a transactional outbox: the jobs exist if and only if the change committed).

  | Event | Job |
  |---|---|
  | `:idea_to_refining`, `:idea_back_to_refining` | wake the refiner |
  | `:idea_to_building` | write the decision log entry, wake the builder |
  | `:mention` (`@<bot id>` in a comment) | wake that bot |
  | `:pr_approved`, `:pr_changes_requested` (a founder answers a PR) | wake the builder |
  | `:question_answered` (an answer or a deferral) | wake the refiner while the card is in Refining |
  | `:idea_to_check`, `:idea_to_done`, `:idea_to_archived` | no wake (founders see the board) |
  | `:comment` (a comment on a card) | no wake (the `:mention` event wakes the bots) |

  Each event also goes to the inbox (`Workflow.Inbox.route/2`, through
  `Workflow.Inbox.Store.add/3`) in the same Multi. A comment that names a
  founder makes an inbox item. A comment by a founder closes the items of
  that founder for the card. A move to Done or to the Archive closes all
  items of the card.

  Only moves (the "Wakes" column of `TalesForge.Board.Transitions`) and
  `@mentions` wake bots. Votes and links wake nobody.

  At most one wake goes to a bot for a card in 2 minutes
  (`TalesForge.Board.WakeMerge`); a second event in that time adds no job.

  Bot wake-ups are `TalesForge.Board.Workers.Notify` jobs (signed webhook
  POSTs); the decision log entry is `TalesForge.Board.Workers.LogDecision`.

  `add/4` queues jobs, so it is an edge: it reads the team config
  (`Workflow.Team.Source`) and gives it to the pure `bots/3`.
  """

  alias Ecto.Multi
  alias TalesForge.Board.{Idea, WakeMerge}
  alias TalesForge.Board.Workers.{LogDecision, Notify}
  alias Workflow.Inbox.Event, as: InboxEvent
  alias Workflow.Inbox.Store, as: InboxStore
  alias Workflow.Team

  @typedoc "A board event."
  @type event ::
          :idea_to_refining
          | :idea_back_to_refining
          | :idea_to_check
          | :idea_to_building
          | :idea_to_done
          | :idea_to_archived
          | :comment
          | :mention
          | :pr_approved
          | :question_answered
          | :pr_changes_requested

  @doc "Adds the jobs of `event` on `idea` (with `extra` details) to `multi`."
  @spec add(Multi.t(), event(), Idea.t(), map()) :: Multi.t()
  def add(multi, event, %Idea{} = idea, extra) do
    team = Workflow.Team.Source.team()

    multi =
      if event == :idea_to_building,
        do:
          Oban.insert(
            multi,
            {:log_decision, idea.id},
            LogDecision.new(%{"idea_id" => idea.id, "founder" => extra[:actor]})
          ),
        else: multi

    team
    |> bots(event, extra)
    |> Enum.reduce(multi, fn bot, acc ->
      Multi.run(acc, {:notify, bot, event, System.unique_integer([:positive])}, fn repo, _ ->
        notify(repo, bot, event, idea, extra)
      end)
    end)
    |> InboxStore.add(team, &inbox_event(event, idea, extra, &1))
  end

  @doc """
  The inbox event of a board event, or nil. `changes` are the Multi changes
  so far: a `:comment` event reads the stored comment there.

      iex> idea = %TalesForge.Board.Idea{id: "i1", title: "T"}
      iex> TalesForge.Board.Events.inbox_event(:idea_to_done, idea, %{}, %{}).type
      :card_closed
      iex> TalesForge.Board.Events.inbox_event(:idea_to_check, idea, %{questions: ["How big?"]}, %{}).questions
      ["How big?"]
      iex> TalesForge.Board.Events.inbox_event(:idea_to_refining, idea, %{}, %{})
      nil
  """
  @spec inbox_event(event(), Idea.t(), map(), map()) :: InboxEvent.t() | nil
  def inbox_event(event, %Idea{id: id, title: title}, _extra, _changes)
      when event in [:idea_to_done, :idea_to_archived],
      do: %InboxEvent{type: :card_closed, idea_id: id, title: title}

  def inbox_event(:comment, %Idea{id: id, title: title}, extra, %{comment: comment}),
    do: %InboxEvent{
      type: :comment,
      source_id: comment.id,
      idea_id: id,
      title: title,
      author: comment.author,
      author_handle: extra[:author_handle],
      mentions: extra[:mentions] || [],
      body: comment.body || ""
    }

  def inbox_event(:idea_to_check, %Idea{id: id, title: title}, extra, _changes),
    do: %InboxEvent{
      type: :check_questions,
      idea_id: id,
      title: title,
      author: extra[:actor],
      questions: extra[:questions] || []
    }

  def inbox_event(:question_answered, %Idea{id: id, title: title}, extra, _changes),
    do: %InboxEvent{
      type: :question_answered,
      idea_id: id,
      title: title,
      author: extra[:actor],
      questions: [get_in(extra, [:question, "text"])] |> Enum.filter(&is_binary/1)
    }

  def inbox_event(event, %Idea{id: id, title: title}, %{from: "check"}, _changes)
      when event in [:idea_to_building, :idea_back_to_refining],
      do: %InboxEvent{type: :check_left, idea_id: id, title: title}

  def inbox_event(_event, _idea, _extra, _changes), do: nil

  @doc """
  The bots an event wakes.

      iex> team = Workflow.Team.example()
      iex> TalesForge.Board.Events.bots(team, :idea_to_building, %{})
      [:bram]
      iex> TalesForge.Board.Events.bots(team, :mention, %{bot: :quill})
      [:quill]
      iex> TalesForge.Board.Events.bots(team, :idea_to_done, %{})
      []
  """
  @spec bots(Team.t(), event(), map()) :: [TalesForge.BoardApi.bot()]
  def bots(team, event, _extra)
      when event in [:idea_to_refining, :idea_back_to_refining],
      do: [Team.bot(team, :refiner)]

  def bots(team, :idea_to_building, _extra), do: [Team.bot(team, :builder)]
  def bots(_team, :mention, %{bot: bot}), do: [bot]

  def bots(team, event, _extra) when event in [:pr_approved, :pr_changes_requested],
    do: [Team.bot(team, :builder)]

  def bots(team, :question_answered, extra),
    do: TalesForge.Board.Transitions.event_wakes(team, :question_answered, extra[:column])

  def bots(_team, _event, _extra), do: []

  # One wake for each bot and card in 2 minutes (WakeMerge); a later event merges.
  defp notify(repo, bot, event, idea, extra) do
    if WakeMerge.wake?(WakeMerge.last_wake_at(repo, bot, idea.id), DateTime.utc_now()),
      do: Oban.insert(Notify.job(bot, event, idea, extra)),
      else: {:ok, :merged}
  end
end
