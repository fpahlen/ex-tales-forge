defmodule TalesForge.Board.Transitions do
  @moduledoc """
  The idea board's card state machine (docs repo
  `docs/design-board-states.md`, approved 2026-10-10). Pure.

  The server checks every move with `allowed?/5`, and the board UI asks the
  same module which moves it can offer (`options/4`) and why a card cannot
  move (`blocker/3`). Each function gets the team config (`Workflow.Team`)
  as its first argument. The refiner, the builder and the checker are the
  bots with these roles in the team config.

  A card changes state only by an explicit move. A move that is not in this
  table is refused. Votes and comments do not move cards.

  States (the stored column names are on the left, the spec names in brackets):
  `ideas` (idea), `refining`, `check` (founder_check), `building`, `done`,
  `parked`, `archived`.

  Archived is outside the board columns: the Archive tile next to Parked
  opens it. A card in Archived keeps its votes, comments and history; the
  ranking, AutoDone, the refiner's pull and the pings skip it. A founder can
  delete an archived card for good (`delete_allowed?/2`).

  | From | To | Who | Gate | Wakes |
  |---|---|---|---|---|
  | ideas | refining | founder | at least 1 upvote and 0 downvotes | refiner |
  | ideas | parked | founder | none | none |
  | refining | check | refiner | refinement has verdict, cost and questions | founders (badge) |
  | refining | ideas | founder | none | none |
  | check | building | founder | all open questions answered or deferred | builder |
  | check | refining | founder | a comment that says what to change | refiner |
  | check | parked | founder | none | none |
  | building | check | builder | linked PR needs founder approval | founders |
  | check (PR) | building | founder | Approve | builder (merge) |
  | building | done | the board (automatic), or the builder | linked PR is on prod | founders (badge) |
  | building | refining | builder or founder | a comment with the blocker | refiner |
  | parked | ideas | founder | none | none |
  | ideas | archived | founder | a short reason | none |
  | parked | archived | founder | a short reason | none |
  | archived | ideas | founder (Restore) | none | none |
  | done | (none) | | done is final | |

  The card facts (`t:card/0`) come from `TalesForge.Board.facts/1`.
  """

  @typedoc "Who moves the card."
  @type actor :: {:founder, String.t()} | {:bot, atom()}

  @typedoc """
  Facts about the card that the gates need:

    * `up`, `down`: the number of upvotes and downvotes
    * `refined`: the refinement has a verdict, a cost and a list of questions
    * `open_questions`: the number of open questions with no answer and not deferred
    * `comment`: the comment that goes with the move (nil or blank for none)
    * `pr`: `nil` (no PR waits), `:awaiting` (a PR waits for a founder's OK)
      or `:approved` (a founder pressed Approve)
    * `pr_linked`: the card has a linked PR
    * `pr_on_prod`: `:ok` when the PR's merge commit is in the running prod
      release, `{:error, reason}` when not (nil: not checked)
  """
  @type card :: %{
          optional(:up) => non_neg_integer(),
          optional(:down) => non_neg_integer(),
          optional(:refined) => boolean(),
          optional(:open_questions) => non_neg_integer(),
          optional(:comment) => String.t() | nil,
          optional(:pr) => nil | :awaiting | :approved,
          optional(:pr_linked) => boolean(),
          optional(:pr_on_prod) => :ok | {:error, String.t()} | nil
        }

  alias Workflow.Team

  @states ~w(ideas refining check building done parked archived)

  @doc """
  The states, in board order.

      iex> TalesForge.Board.Transitions.states()
      ["ideas", "refining", "check", "building", "done", "parked", "archived"]
  """
  @spec states() :: [String.t()]
  def states, do: @states

  @doc """
  The display label of a state, from the team config.

      iex> team = Workflow.Team.example()
      iex> TalesForge.Board.Transitions.label(team, "check")
      "Founder check"
  """
  @spec label(Team.t(), String.t()) :: String.t()
  def label(%Team{} = team, state), do: Team.label(team, state)

  @doc """
  `:ok` when `actor` may move the card from `from` to `to`, else
  `{:error, reason}`, a short sentence for the UI or the bot.

  Ideas → Refining: a founder, with at least 1 upvote and 0 downvotes.

      iex> team = Workflow.Team.example()
      iex> alias TalesForge.Board.Transitions, as: T
      iex> T.allowed?(team, %{up: 1, down: 0}, "ideas", "refining", {:founder, "a@x"})
      :ok
      iex> T.allowed?(team, %{up: 0, down: 0}, "ideas", "refining", {:founder, "a@x"})
      {:error, "Needs an upvote."}
      iex> T.allowed?(team, %{up: 2, down: 1}, "ideas", "refining", {:founder, "a@x"})
      {:error, "Has a downvote. A founder must change their vote first."}
      iex> T.allowed?(team, %{up: 3, down: 0}, "ideas", "refining", {:bot, :rita})
      {:error, "A founder moves this card."}

  Ideas → Parked: a founder, no gate.

      iex> team = Workflow.Team.example()
      iex> TalesForge.Board.Transitions.allowed?(team, %{down: 1}, "ideas", "parked", {:founder, "a@x"})
      :ok
      iex> TalesForge.Board.Transitions.allowed?(team, %{}, "ideas", "parked", {:bot, :rita})
      {:error, "A founder moves this card."}

  Refining → Founder check: the refiner bot, when the refinement has a verdict, a cost and questions.

      iex> team = Workflow.Team.example()
      iex> alias TalesForge.Board.Transitions, as: T
      iex> T.allowed?(team, %{refined: true}, "refining", "check", {:bot, :rita})
      :ok
      iex> T.allowed?(team, %{refined: false}, "refining", "check", {:bot, :rita})
      {:error, "Waits for Rita's refinement: verdict, cost and questions."}
      iex> T.allowed?(team, %{refined: true}, "refining", "check", {:founder, "a@x"})
      {:error, "Rita moves this card when the refinement is complete."}

  Refining → Ideas: a founder, no gate.

      iex> team = Workflow.Team.example()
      iex> TalesForge.Board.Transitions.allowed?(team, %{}, "refining", "ideas", {:founder, "a@x"})
      :ok
      iex> TalesForge.Board.Transitions.allowed?(team, %{}, "refining", "ideas", {:bot, :rita})
      {:error, "A founder moves this card."}

  Founder check → Building: a founder, when every open question has an
  answer or is deferred (each question has its own answer box and Defer
  toggle on the full card). The move needs no comment.

      iex> team = Workflow.Team.example()
      iex> alias TalesForge.Board.Transitions, as: T
      iex> T.allowed?(team, %{open_questions: 0}, "check", "building", {:founder, "a@x"})
      :ok
      iex> T.allowed?(team, %{open_questions: 2}, "check", "building", {:founder, "a@x"})
      {:error, "Answer or defer the 2 open questions."}
      iex> T.allowed?(team, %{open_questions: 1, comment: "a comment is not an answer"}, "check", "building", {:founder, "a@x"})
      {:error, "Answer or defer the 1 open question."}
      iex> T.allowed?(team, %{}, "check", "building", {:bot, :bram})
      {:error, "A founder moves this card."}

  Founder check → Refining: a founder, with a comment that says what to change.

      iex> team = Workflow.Team.example()
      iex> alias TalesForge.Board.Transitions, as: T
      iex> T.allowed?(team, %{comment: "Make it cheaper."}, "check", "refining", {:founder, "a@x"})
      :ok
      iex> T.allowed?(team, %{comment: " "}, "check", "refining", {:founder, "a@x"})
      {:error, "Write a comment that says what to change."}

  Founder check → Parked: a founder, no gate.

      iex> team = Workflow.Team.example()
      iex> TalesForge.Board.Transitions.allowed?(team, %{}, "check", "parked", {:founder, "a@x"})
      :ok

  Building → Founder check: nobody. Founder check is only for the refined
  idea. A PR that waits for a founder's OK keeps the card in Building (see
  `pr_answer/2`).

      iex> team = Workflow.Team.example()
      iex> alias TalesForge.Board.Transitions, as: T
      iex> T.allowed?(team, %{pr: :awaiting}, "building", "check", {:bot, :bram})
      {:error, "Founder check is for the refined idea. A PR waits for approval in Building."}
      iex> T.allowed?(team, %{pr: :awaiting}, "building", "check", {:founder, "a@x"})
      {:error, "Founder check is for the refined idea. A PR waits for approval in Building."}
      iex> T.allowed?(team, %{pr: :awaiting, open_questions: 0}, "check", "building", {:founder, "a@x"})
      :ok

  Building → Done: the board itself (`{:bot, :board}`, automatically after
  each prod boot, `TalesForge.Board.Workers.AutoDone`) or the builder bot (the manual
  fallback), when the linked PR is on prod: its merge commit is
  in the running prod release (`pr_on_prod`, checked by
  `TalesForge.Board.OnProd` when the builder bot moves the card).

      iex> team = Workflow.Team.example()
      iex> alias TalesForge.Board.Transitions, as: T
      iex> T.allowed?(team, %{pr_linked: true}, "building", "done", {:bot, :bram})
      :ok
      iex> T.allowed?(team, %{pr_linked: false}, "building", "done", {:bot, :bram})
      {:error, "Link the PR that is on prod first."}
      iex> T.allowed?(team, %{pr_linked: true, pr_on_prod: {:error, "PR #7 is not in the prod release yet."}}, "building", "done", {:bot, :bram})
      {:error, "PR #7 is not in the prod release yet."}
      iex> T.allowed?(team, %{pr_linked: true, pr_on_prod: :ok}, "building", "done", {:bot, :board})
      :ok
      iex> T.allowed?(team, %{pr_linked: true, pr_on_prod: {:error, "PR #7 is not in the prod release yet."}}, "building", "done", {:bot, :board})
      {:error, "PR #7 is not in the prod release yet."}
      iex> T.allowed?(team, %{pr_linked: false}, "building", "done", {:bot, :board})
      {:error, "Link the PR that is on prod first."}
      iex> T.allowed?(team, %{pr_linked: true}, "building", "done", {:bot, :rita})
      {:error, "Bram moves this card when its PR is on prod."}
      iex> T.allowed?(team, %{pr_linked: true}, "building", "done", {:founder, "a@x"})
      {:error, "Bram moves this card when its PR is on prod."}

  Building → Refining: the builder bot or a founder, with a comment that names the blocker.

      iex> team = Workflow.Team.example()
      iex> alias TalesForge.Board.Transitions, as: T
      iex> T.allowed?(team, %{comment: "The API has no search."}, "building", "refining", {:bot, :bram})
      :ok
      iex> T.allowed?(team, %{comment: "Too slow."}, "building", "refining", {:founder, "a@x"})
      :ok
      iex> T.allowed?(team, %{}, "building", "refining", {:bot, :bram})
      {:error, "Write a comment that names the blocker."}
      iex> T.allowed?(team, %{comment: "x"}, "building", "refining", {:bot, :rita})
      {:error, "Bram or a founder moves this card."}

  Parked → Ideas: a founder, no gate.

      iex> team = Workflow.Team.example()
      iex> TalesForge.Board.Transitions.allowed?(team, %{}, "parked", "ideas", {:founder, "a@x"})
      :ok

  Done is final; moves not in the table are refused.

      iex> team = Workflow.Team.example()
      iex> alias TalesForge.Board.Transitions, as: T
      iex> T.allowed?(team, %{}, "done", "ideas", {:founder, "a@x"})
      {:error, "Done is final. Make a new card that links to this one."}
      iex> T.allowed?(team, %{}, "refining", "parked", {:founder, "a@x"})
      {:error, "Refining (Rita) to Parked is not a move on the board."}
      iex> T.allowed?(team, %{}, "ideas", "ideas", {:founder, "a@x"})
      {:error, "The card is already there."}

  Ideas or Parked → Archived: a founder, with a short reason (the reason
  box works like the one for a downvote). Bots and other columns cannot
  archive.

      iex> team = Workflow.Team.example()
      iex> alias TalesForge.Board.Transitions, as: T
      iex> T.allowed?(team, %{comment: "Same as the chat card."}, "ideas", "archived", {:founder, "a@x"})
      :ok
      iex> T.allowed?(team, %{comment: "Spam."}, "parked", "archived", {:founder, "a@x"})
      :ok
      iex> T.allowed?(team, %{comment: " "}, "ideas", "archived", {:founder, "a@x"})
      {:error, "Write a short reason for the archive."}
      iex> T.allowed?(team, %{comment: "x"}, "ideas", "archived", {:bot, :quill})
      {:error, "A founder moves this card."}
      iex> T.allowed?(team, %{comment: "x"}, "check", "archived", {:founder, "a@x"})
      {:error, "Founder check to Archive is not a move on the board."}

  Archived → Ideas (Restore): a founder, no gate. An archived card goes
  only back to Ideas.

      iex> team = Workflow.Team.example()
      iex> alias TalesForge.Board.Transitions, as: T
      iex> T.allowed?(team, %{}, "archived", "ideas", {:founder, "a@x"})
      :ok
      iex> T.allowed?(team, %{}, "archived", "ideas", {:bot, :rita})
      {:error, "A founder moves this card."}
      iex> T.allowed?(team, %{}, "archived", "parked", {:founder, "a@x"})
      {:error, "Restore the card to Ideas first."}
  """
  @spec allowed?(Team.t(), card(), String.t(), String.t(), actor()) :: :ok | {:error, String.t()}
  def allowed?(_team, _card, same, same, _actor), do: {:error, "The card is already there."}

  def allowed?(_team, _card, "done", _to, _actor),
    do: {:error, "Done is final. Make a new card that links to this one."}

  def allowed?(_team, card, "ideas", "refining", actor) do
    with :ok <- founder(actor) do
      cond do
        n(card, :down) > 0 -> {:error, "Has a downvote. A founder must change their vote first."}
        n(card, :up) < 1 -> {:error, "Needs an upvote."}
        true -> :ok
      end
    end
  end

  def allowed?(_team, _card, "ideas", "parked", actor), do: founder(actor)

  def allowed?(team, card, "refining", "check", {:bot, bot}) when is_atom(bot) do
    if bot == Team.bot(team, :refiner),
      do: need(card[:refined] == true, refine_wait(team)),
      else: refining_check_error(team)
  end

  def allowed?(team, _card, "refining", "check", _actor), do: refining_check_error(team)

  def allowed?(_team, _card, "refining", "ideas", actor), do: founder(actor)

  def allowed?(_team, card, "check", "building", actor) do
    with :ok <- founder(actor) do
      q = n(card, :open_questions)

      need(
        q == 0,
        "Answer or defer the #{q} open #{if q == 1, do: "question", else: "questions"}."
      )
    end
  end

  def allowed?(_team, card, "check", "refining", actor) do
    with :ok <- founder(actor),
         do: need(comment?(card), "Write a comment that says what to change.")
  end

  def allowed?(_team, _card, "check", "parked", actor), do: founder(actor)

  def allowed?(_team, _card, "building", "check", _actor),
    do: {:error, "Founder check is for the refined idea. A PR waits for approval in Building."}

  def allowed?(team, card, "building", "done", {:bot, bot}) when is_atom(bot) do
    if bot in [:board, Team.bot(team, :builder)],
      do: done_gate(card),
      else: done_error(team)
  end

  def allowed?(team, _card, "building", "done", _actor), do: done_error(team)

  def allowed?(team, card, "building", "refining", actor) do
    if actor == {:bot, Team.bot(team, :builder)} or elem(actor, 0) == :founder,
      do: need(comment?(card), "Write a comment that names the blocker."),
      else: {:error, "#{Team.bot_name(team, :builder)} or a founder moves this card."}
  end

  def allowed?(_team, _card, "parked", "ideas", actor), do: founder(actor)

  def allowed?(_team, card, from, "archived", actor) when from in ["ideas", "parked"] do
    with :ok <- founder(actor),
         do: need(comment?(card), "Write a short reason for the archive.")
  end

  def allowed?(_team, _card, "archived", "ideas", actor), do: founder(actor)

  def allowed?(_team, _card, "archived", _to, _actor),
    do: {:error, "Restore the card to Ideas first."}

  def allowed?(team, _card, from, to, _actor),
    do: {:error, "#{label(team, from)} to #{label(team, to)} is not a move on the board."}

  @doc """
  Can the actor Approve or Request changes on the card's PR? Only a founder,
  and only while the card is in Building with a PR that waits for an OK
  (`pr: :awaiting`). The card stays in Building. Approve wakes the builder
  (`pr.approved`) to merge and ship. Request changes wakes the builder
  (`pr.changes_requested`) with the comment.

      iex> team = Workflow.Team.example()
      iex> alias TalesForge.Board.Transitions, as: T
      iex> T.pr_answer(team, %{pr: :awaiting}, "building", {:founder, "a@x"})
      :ok
      iex> T.pr_answer(team, %{pr: :awaiting}, "building", {:bot, :bram})
      {:error, "Only a founder can answer a PR."}
      iex> T.pr_answer(team, %{pr: :approved}, "building", {:founder, "a@x"})
      {:error, "No PR waits for approval on this card."}
      iex> T.pr_answer(team, %{pr: :awaiting}, "check", {:founder, "a@x"})
      {:error, "A PR waits for approval in Building. This card is in Founder check."}
  """
  @spec pr_answer(Team.t(), card(), String.t(), actor()) :: :ok | {:error, String.t()}
  def pr_answer(_team, _card, _column, {:bot, _}), do: {:error, "Only a founder can answer a PR."}

  def pr_answer(_team, card, "building", _actor),
    do: need(card[:pr] == :awaiting, "No PR waits for approval on this card.")

  def pr_answer(team, _card, column, _actor),
    do: {:error, "A PR waits for approval in Building. This card is in #{label(team, column)}."}

  @doc """
  Who an event that is not a move wakes. An answer or a deferral of an
  open question (`question.answered`) wakes the refiner while the card is in
  Refining. In other columns the founders see it on the card.

      iex> team = Workflow.Team.example()
      iex> alias TalesForge.Board.Transitions, as: T
      iex> {T.event_wakes(team, :question_answered, "refining"), T.event_wakes(team, :question_answered, "check")}
      {[:rita], []}
  """
  @spec event_wakes(Team.t(), atom(), String.t() | nil) :: [atom()]
  def event_wakes(team, :question_answered, "refining"), do: [Team.bot(team, :refiner)]
  def event_wakes(_team, _event, _column), do: []

  @doc """
  Who a move wakes: the refiner, the builder (their bot ids) and `:founders`
  (a badge on the board, no webhook). Empty for moves that wake nobody.

      iex> team = Workflow.Team.example()
      iex> alias TalesForge.Board.Transitions, as: T
      iex> {T.wakes(team, "ideas", "refining"), T.wakes(team, "check", "refining"), T.wakes(team, "building", "refining")}
      {[:rita], [:rita], [:rita]}
      iex> {T.wakes(team, "check", "building"), T.wakes(team, "refining", "check"), T.wakes(team, "building", "check"), T.wakes(team, "building", "done")}
      {[:bram], [:founders], [:founders], [:founders]}
      iex> {T.wakes(team, "ideas", "parked"), T.wakes(team, "refining", "ideas"), T.wakes(team, "parked", "ideas"), T.wakes(team, "check", "parked")}
      {[], [], [], []}
      iex> {T.wakes(team, "ideas", "archived"), T.wakes(team, "parked", "archived"), T.wakes(team, "archived", "ideas")}
      {[], [], []}
  """
  @spec wakes(Team.t(), String.t(), String.t()) :: [atom()]
  def wakes(team, _from, "refining"), do: [Team.bot(team, :refiner)]
  def wakes(team, "check", "building"), do: [Team.bot(team, :builder)]

  def wakes(_team, from, to)
      when {from, to} in [{"refining", "check"}, {"building", "check"}, {"building", "done"}],
      do: [:founders]

  def wakes(_team, _from, _to), do: []

  @doc """
  Every other state with the answer of `allowed?/5` for `actor`, for the UI's
  "Move to" list and drag targets. A move that needs a comment counts as
  possible when the only gate is the comment (the form asks for it).
  Archived is not a drag target: the Archive button asks for the reason
  (`archivable?/3`).

      iex> team = Workflow.Team.example()
      iex> TalesForge.Board.Transitions.options(team, %{up: 0}, "ideas", {:founder, "a@x"})
      [{"refining", {:error, "Needs an upvote."}}, {"parked", :ok}]
      iex> TalesForge.Board.Transitions.options(team, %{}, "check", {:founder, "a@x"}) |> Enum.map(&elem(&1, 0))
      ["refining", "building", "parked"]
  """
  @spec options(Team.t(), card(), String.t(), actor()) ::
          [{String.t(), :ok | {:error, String.t()}}]
  def options(team, card, from, actor) do
    card = Map.put(card, :comment, "(comment)")

    for to <- @states, to != from, to != "archived", row?(team, from, to, actor) do
      {to, allowed?(team, card, from, to, actor)}
    end
  end

  @steps %{
    "ideas" => %{back: nil, forward: "refining", hold: "parked"},
    "refining" => %{back: "ideas", forward: "check", hold: nil},
    "check" => %{back: "refining", forward: "building", hold: "parked"},
    "building" => %{back: "refining", forward: "done", hold: nil},
    "parked" => %{back: nil, forward: "ideas", hold: nil},
    "done" => %{back: nil, forward: nil, hold: nil},
    "archived" => %{back: nil, forward: nil, hold: nil}
  }

  @typedoc "A move button on the full card."
  @type button :: %{
          kind: :back | :forward | :hold,
          to: String.t(),
          label: String.t(),
          answer: :ok | {:error, String.t()},
          needs_comment: boolean()
        }

  @doc """
  The Back, Forward and On hold buttons of a card in `from` for `actor`. Back
  is the previous state, Forward the next one, On hold is Parked (from
  Parked, Forward goes back to Ideas). Only the moves the actor may make are
  in the list. `answer` is `allowed?/5` for the card as it is (a failed gate
  disables the button and shows the reason). `needs_comment` is true when the
  move needs a comment: the button opens a comment box, and the gate is
  checked again with the comment.

      iex> team = Workflow.Team.example()
      iex> alias TalesForge.Board.Transitions, as: T
      iex> T.buttons(team, %{up: 0}, "ideas", {:founder, "a@x"})
      [%{kind: :forward, to: "refining", label: "Send to Refining", answer: {:error, "Needs an upvote."}, needs_comment: false},
       %{kind: :hold, to: "parked", label: "Put on hold", answer: :ok, needs_comment: false}]
      iex> T.buttons(team, %{open_questions: 0}, "check", {:founder, "a@x"}) |> Enum.map(&{&1.kind, &1.to, &1.needs_comment})
      [{:back, "refining", true}, {:forward, "building", false}, {:hold, "parked", false}]
      iex> T.buttons(team, %{}, "refining", {:founder, "a@x"}) |> Enum.map(&{&1.kind, &1.to})
      [{:back, "ideas"}]
      iex> T.buttons(team, %{}, "building", {:founder, "a@x"}) |> Enum.map(&{&1.kind, &1.to, &1.needs_comment})
      [{:back, "refining", true}]
      iex> T.buttons(team, %{}, "parked", {:founder, "a@x"}) |> Enum.map(&{&1.kind, &1.to})
      [{:forward, "ideas"}]
      iex> T.buttons(team, %{}, "done", {:founder, "a@x"})
      []
      iex> T.buttons(team, %{}, "archived", {:founder, "a@x"})
      []
  """
  @spec buttons(Team.t(), card(), String.t(), actor()) :: [button()]
  def buttons(team, card, from, actor) do
    steps = Map.get(@steps, from, %{})

    for kind <- [:back, :forward, :hold],
        to = steps[kind],
        to != nil,
        row?(team, from, to, actor) do
      plain = Map.put(card, :comment, nil)
      as_is = allowed?(team, Map.merge(card, %{comment: card[:comment]}), from, to, actor)

      needs_comment =
        allowed?(team, plain, from, to, actor) != :ok and
          allowed?(team, Map.put(card, :comment, "(comment)"), from, to, actor) == :ok and
          comment_gate?(allowed?(team, plain, from, to, actor))

      answer = if needs_comment, do: :ok, else: as_is

      %{
        kind: kind,
        to: to,
        label: step_label(team, from, to),
        answer: answer,
        needs_comment: needs_comment
      }
    end
  end

  @doc """
  True when `actor` sees the Archive button on a card in `from`: a founder,
  on a card in Ideas or Parked only.

      iex> team = Workflow.Team.example()
      iex> alias TalesForge.Board.Transitions, as: T
      iex> for c <- ~w(ideas parked refining check building done archived), do: {c, T.archivable?(team, c, {:founder, "a@x"})}
      [{"ideas", true}, {"parked", true}, {"refining", false}, {"check", false}, {"building", false}, {"done", false}, {"archived", false}]
      iex> T.archivable?(team, "ideas", {:bot, :bram})
      false
  """
  @spec archivable?(Team.t(), String.t(), actor()) :: boolean()
  def archivable?(team, from, actor),
    do:
      from in ["ideas", "parked"] and
        allowed?(team, %{comment: "x"}, from, "archived", actor) == :ok

  @doc """
  `:ok` when `actor` may delete a card in `column` for good: a founder, and
  only a card in Archived. Bots cannot delete. (The board also refuses the
  QA session, `TalesForge.Board.delete_archived/3`.)

      iex> alias TalesForge.Board.Transitions, as: T
      iex> T.delete_allowed?("archived", {:founder, "a@x"})
      :ok
      iex> T.delete_allowed?("ideas", {:founder, "a@x"})
      {:error, "Archive the card first. Then you can delete it."}
      iex> T.delete_allowed?("archived", {:bot, :bram})
      {:error, "Only a founder can delete a card."}
  """
  @spec delete_allowed?(String.t(), actor()) :: :ok | {:error, String.t()}
  def delete_allowed?(_column, {:bot, _}), do: {:error, "Only a founder can delete a card."}
  def delete_allowed?("archived", {:founder, _}), do: :ok

  def delete_allowed?(_column, _actor),
    do: {:error, "Archive the card first. Then you can delete it."}

  @doc """
  The button label of a move, named by its target step. The server and the
  UI share these.

      iex> team = Workflow.Team.example()
      iex> alias TalesForge.Board.Transitions, as: T
      iex> for {f, t} <- [{"ideas", "refining"}, {"ideas", "parked"}, {"refining", "check"}, {"refining", "ideas"}], do: T.step_label(team, f, t)
      ["Send to Refining", "Put on hold", "Send to Founder check", "Back to Ideas"]
      iex> for {f, t} <- [{"check", "building"}, {"check", "refining"}, {"check", "parked"}, {"building", "check"}], do: T.step_label(team, f, t)
      ["Start building", "Back to Refining", "Put on hold", "Send to Founder check"]
      iex> for {f, t} <- [{"building", "done"}, {"building", "refining"}, {"parked", "ideas"}], do: T.step_label(team, f, t)
      ["Mark as done", "Back to Refining", "Back to Ideas"]
      iex> for {f, t} <- [{"ideas", "archived"}, {"archived", "ideas"}], do: T.step_label(team, f, t)
      ["Archive", "Restore to Ideas"]
  """
  @spec step_label(Team.t(), String.t(), String.t()) :: String.t()
  def step_label(_team, _from, "parked"), do: "Put on hold"
  def step_label(_team, _from, "archived"), do: "Archive"
  def step_label(_team, "archived", "ideas"), do: "Restore to Ideas"
  def step_label(_team, _from, "building"), do: "Start building"
  def step_label(_team, _from, "done"), do: "Mark as done"
  def step_label(_team, "ideas", "refining"), do: "Send to Refining"
  def step_label(_team, _from, "refining"), do: "Back to Refining"
  def step_label(_team, _from, "ideas"), do: "Back to Ideas"
  def step_label(team, _from, to), do: "Send to #{label(team, to)}"

  defp comment_gate?({:error, reason}), do: reason =~ "comment"
  defp comment_gate?(_), do: false

  # The actor may make this move when its gate is met.
  defp row?(team, from, to, actor) do
    open = %{up: 1, down: 0, refined: true, open_questions: 0, comment: "x", pr_linked: true}

    Enum.any?([:awaiting, :approved], fn pr ->
      allowed?(team, Map.put(open, :pr, pr), from, to, actor) == :ok
    end)
  end

  @doc """
  Why a card cannot take its next step, or nil when it can (or the next step
  is a bot's and its gate is met). The next steps: Ideas → Refining (a
  founder), Refining → Founder check (the refiner), Founder check → Building
  (a founder), Building → Done (the builder). Shown on the card.

      iex> team = Workflow.Team.example()
      iex> alias TalesForge.Board.Transitions, as: T
      iex> T.blocker(team, %{up: 0, down: 0}, "ideas")
      "Needs an upvote."
      iex> T.blocker(team, %{up: 1, down: 0}, "ideas")
      nil
      iex> T.blocker(team, %{refined: false}, "refining")
      "Waits for Rita's refinement: verdict, cost and questions."
      iex> T.blocker(team, %{open_questions: 1}, "check")
      "Answer or defer the 1 open question."
      iex> T.blocker(team, %{}, "done")
      nil
  """
  @spec blocker(Team.t(), card(), String.t()) :: String.t() | nil
  def blocker(team, card, from) do
    step =
      %{
        "ideas" => {"refining", {:founder, "founder"}},
        "refining" => {"check", {:bot, Team.bot(team, :refiner)}},
        "check" => {"building", {:founder, "founder"}},
        "building" => {"done", {:bot, Team.bot(team, :builder)}}
      }[from]

    with {to, actor} <- step,
         {:error, reason} <- allowed?(team, card, from, to, actor) do
      reason
    else
      _ -> nil
    end
  end

  @doc """
  The actor as a string for the move log (`founder email` or `bot:<id>`).

      iex> TalesForge.Board.Transitions.actor_name({:bot, :rita})
      "bot:rita"
  """
  @spec actor_name(actor()) :: String.t()
  def actor_name({:founder, email}), do: email
  def actor_name({:bot, bot}), do: "bot:#{bot}"

  defp done_gate(card) do
    case {card[:pr_linked], card[:pr_on_prod]} do
      {true, {:error, reason}} -> {:error, reason}
      {true, _} -> :ok
      _ -> {:error, "Link the PR that is on prod first."}
    end
  end

  defp done_error(team),
    do: {:error, "#{Team.bot_name(team, :builder)} moves this card when its PR is on prod."}

  defp refine_wait(team),
    do: "Waits for #{Team.bot_name(team, :refiner)}'s refinement: verdict, cost and questions."

  defp refining_check_error(team),
    do:
      {:error,
       "#{Team.bot_name(team, :refiner)} moves this card when the refinement is complete."}

  defp founder({:founder, _}), do: :ok
  defp founder(_), do: {:error, "A founder moves this card."}

  defp need(true, _reason), do: :ok
  defp need(_, reason), do: {:error, reason}

  defp n(card, key), do: Map.get(card, key) || 0

  defp comment?(card), do: is_binary(card[:comment]) and String.trim(card[:comment]) != ""
end
