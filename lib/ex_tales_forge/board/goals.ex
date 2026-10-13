defmodule TalesForge.Board.Goals do
  @moduledoc """
  Goals on the founders' idea board (docs repo `docs/design-idea-board.md`,
  "Goals").

  - A goal has a title, an outcome line, an optional target date and a sort
    position (`TalesForge.Board.Goal`). A month target uses the last day of
    the month (`month_end/2`).
  - Founders vote +1 or -1 on a goal, like on a card. A -1 needs a reason.
    Goals are in score order (net votes), then in sort order.
  - A card has zero or one goal. Only a founder changes the goal of a card:
    bots (`bot:` actors) and the QA session (`TalesForge.QaLogin`) cannot.
  - The goals strip: for each goal, the Done cards over all its cards
    (archived cards are not counted) and the time left in Stockholm days, and
    the count of cards without a goal.
  - An open goal lists its cards that are not Done or archived
    (`open_cards/1`). A founder adds a card without a goal from
    `unassigned_cards/0`. The goal of a card is the only link: there is no
    task table.
  - The north star is a header line, not a goal (`north_star/0`).
  """
  import Ecto.Query

  alias TalesForge.Board.{Goal, GoalVote, Idea}
  alias TalesForge.Repo

  @zone "Europe/Stockholm"

  @north_star %{
    text: "First paying customer we don't personally know",
    target_label: "Apr 2027",
    target_date: ~D[2027-04-30]
  }

  @typedoc "An error with a message for the founders."
  @type error :: {:error, String.t() | Ecto.Changeset.t()}

  @typedoc "One goal on the strip."
  @type row :: %{
          goal: Goal.t(),
          score: integer(),
          up: non_neg_integer(),
          down: non_neg_integer(),
          done: non_neg_integer(),
          total: non_neg_integer(),
          days: integer() | nil,
          countdown: String.t() | nil,
          overdue: boolean()
        }

  @doc "The north star: a header line with its own target date (the end of April 2027). It is not a goal."
  @spec north_star() :: %{text: String.t(), target_label: String.t(), target_date: Date.t()}
  def north_star, do: @north_star

  @doc """
  The last day of a month. A month-range target ("Oct-Nov 2026") uses the
  last day of the last month.

      iex> TalesForge.Board.Goals.month_end(2027, 2)
      ~D[2027-02-28]
      iex> TalesForge.Board.Goals.month_end(2028, 2)
      ~D[2028-02-29]
      iex> TalesForge.Board.Goals.month_end(2026, 12)
      ~D[2026-12-31]
  """
  @spec month_end(integer(), 1..12) :: Date.t()
  def month_end(year, month), do: year |> Date.new!(month, 1) |> Date.end_of_month()

  @doc """
  The Stockholm calendar day of `now`.

      iex> TalesForge.Board.Goals.stockholm_today(~U[2026-10-24 22:30:00Z])
      ~D[2026-10-25]
      iex> TalesForge.Board.Goals.stockholm_today(~U[2026-12-31 22:59:59Z])
      ~D[2026-12-31]
  """
  @spec stockholm_today(DateTime.t()) :: Date.t()
  def stockholm_today(now),
    do: now |> DateTime.shift_zone!(@zone, TimeZoneInfo.TimeZoneDatabase) |> DateTime.to_date()

  @doc """
  The days from today in Stockholm to `target` (negative once it is past),
  or nil without a target. A day is a Stockholm calendar day, so a DST
  change does not change the count.
  """
  @spec days_left(Date.t() | nil, DateTime.t()) :: integer() | nil
  def days_left(nil, _now), do: nil
  def days_left(%Date{} = target, now), do: Date.diff(target, stockholm_today(now))

  @doc """
  The countdown text for a number of days left.

      iex> TalesForge.Board.Goals.countdown(24)
      "24 days remaining"
      iex> TalesForge.Board.Goals.countdown(1)
      "1 day remaining"
      iex> TalesForge.Board.Goals.countdown(0)
      "Due today"
      iex> TalesForge.Board.Goals.countdown(-1)
      "1 day overdue"
      iex> TalesForge.Board.Goals.countdown(-5)
      "5 days overdue"
      iex> TalesForge.Board.Goals.countdown(nil)
      nil
  """
  @spec countdown(integer() | nil) :: String.t() | nil
  def countdown(nil), do: nil
  def countdown(0), do: "Due today"
  def countdown(1), do: "1 day remaining"
  def countdown(-1), do: "1 day overdue"
  def countdown(n) when n > 1, do: "#{n} days remaining"
  def countdown(n), do: "#{-n} days overdue"

  @doc "All goals with their votes, best score first, then in sort order."
  @spec list() :: [Goal.t()]
  def list do
    Goal
    |> Repo.all()
    |> Repo.preload(:votes)
    |> Enum.sort_by(&{-score(&1), &1.sort, &1.title})
  end

  @doc "A goal by id with its votes, or nil."
  @spec get(String.t() | nil) :: Goal.t() | nil
  def get(id) when is_binary(id) do
    case Ecto.UUID.cast(id) do
      {:ok, uuid} -> Goal |> Repo.get(uuid) |> Repo.preload(:votes)
      :error -> nil
    end
  end

  def get(_id), do: nil

  @doc "The net votes on a goal (+1s minus -1s)."
  @spec score(Goal.t()) :: integer()
  def score(%Goal{votes: votes}) when is_list(votes), do: Enum.sum(Enum.map(votes, & &1.value))

  @doc "The value of `founder`'s vote on the goal (1, -1) or nil."
  @spec vote_of(Goal.t(), String.t() | nil) :: 1 | -1 | nil
  def vote_of(%Goal{votes: votes}, founder) do
    founder = founder && String.downcase(founder)
    Enum.find_value(votes, &(&1.founder == founder && &1.value))
  end

  @doc """
  Sets `founder`'s vote on a goal to 1 or -1. A -1 needs a `reason`. The
  same value again takes the vote back; the other value changes it. Bots and
  the QA session do not vote on goals.
  """
  @spec vote(Goal.t(), String.t(), 1 | -1, String.t() | nil) :: {:ok, Goal.t()} | error()
  def vote(goal, founder, value, reason \\ nil)

  def vote(%Goal{} = goal, founder, value, reason) when value in [1, -1] do
    if founder?(founder) do
      founder = founder |> String.trim() |> String.downcase()
      reason = if is_binary(reason) and String.trim(reason) != "", do: String.trim(reason)

      result =
        case Repo.get_by(GoalVote, goal_id: goal.id, founder: founder) do
          %GoalVote{value: ^value} = v ->
            Repo.delete(v)

          %GoalVote{} = v ->
            v |> GoalVote.changeset(%{value: value, reason: reason}) |> Repo.update()

          nil ->
            %GoalVote{}
            |> GoalVote.changeset(%{
              goal_id: goal.id,
              founder: founder,
              value: value,
              reason: reason
            })
            |> Repo.insert()
        end

      case result do
        {:ok, _} ->
          broadcast()
          {:ok, get(goal.id)}

        {:error, %Ecto.Changeset{errors: [{:reason, _} | _]}} ->
          {:error, "A downvote needs a reason. Write what needs work."}

        other ->
          other
      end
    else
      {:error, "Only a founder votes on a goal."}
    end
  end

  def vote(_goal, _founder, _value, _reason), do: {:error, "A vote is +1 or -1."}

  @doc """
  Sets the goal of a card (`goal_id` nil removes it). Only a founder can do
  this. A bot (`bot:` actor) and the QA session get an error.
  """
  @spec set_card_goal(Idea.t(), String.t() | term(), String.t() | nil) ::
          {:ok, Idea.t()} | error()
  def set_card_goal(%Idea{} = idea, actor, goal_id) do
    goal_id = if goal_id in [nil, ""], do: nil, else: goal_id

    cond do
      not founder?(actor) ->
        {:error, "Only a founder changes the goal of a card."}

      goal_id != nil and get(goal_id) == nil ->
        {:error, "That goal is gone."}

      true ->
        with {:ok, idea} <- idea |> Ecto.Changeset.change(goal_id: goal_id) |> Repo.update() do
          broadcast()
          {:ok, TalesForge.Board.get_idea!(idea.id)}
        end
    end
  end

  @doc """
  The cards of a goal that are not Done and not archived, in board column
  order, then oldest first. Parked cards are in the list.
  """
  @spec open_cards(String.t()) :: [Idea.t()]
  def open_cards(goal_id) when is_binary(goal_id) do
    from(i in Idea, where: i.goal_id == ^goal_id and i.column not in ["done", "archived"])
    |> Repo.all()
    |> sort_cards()
  end

  @doc "The cards without a goal that are not Done and not archived."
  @spec unassigned_cards() :: [Idea.t()]
  def unassigned_cards do
    from(i in Idea, where: is_nil(i.goal_id) and i.column not in ["done", "archived"])
    |> Repo.all()
    |> sort_cards()
  end

  defp sort_cards(cards) do
    order = TalesForge.Board.Transitions.states() |> Enum.with_index() |> Map.new()
    Enum.sort_by(cards, &{Map.get(order, &1.column, 99), DateTime.to_unix(&1.inserted_at)})
  end

  @doc "True for a founder (an email); false for a bot (`bot:`) and for the QA session."
  @spec founder?(term()) :: boolean()
  def founder?("bot:" <> _), do: false

  def founder?(actor) when is_binary(actor) do
    actor = actor |> String.trim() |> String.downcase()
    actor != "" and actor != String.downcase(TalesForge.QaLogin.email())
  end

  def founder?(_actor), do: false

  @doc """
  The goals strip at `now`: the north star (with its days left) and each
  goal in score order with its votes, its progress (Done cards over all its
  cards; archived cards are not counted) and its countdown, plus the count of
  cards without a goal (`unassigned`, archived cards not counted).
  """
  @spec strip(DateTime.t()) :: %{
          north_star: map(),
          goals: [row()],
          unassigned: non_neg_integer()
        }
  def strip(now \\ DateTime.utc_now()) do
    counts =
      from(i in Idea,
        where: i.column != "archived",
        group_by: i.goal_id,
        select: {i.goal_id, count(i.id), filter(count(i.id), i.column == "done")}
      )
      |> Repo.all()
      |> Map.new(fn {goal_id, total, done} -> {goal_id, {total, done}} end)

    {unassigned, _} = Map.get(counts, nil, {0, 0})
    ns_days = days_left(@north_star.target_date, now)

    %{
      north_star: Map.merge(@north_star, %{days: ns_days, countdown: countdown(ns_days)}),
      unassigned: unassigned,
      goals:
        Enum.map(list(), fn goal ->
          {total, done} = Map.get(counts, goal.id, {0, 0})
          days = days_left(goal.target_date, now)

          %{
            goal: goal,
            score: score(goal),
            up: Enum.count(goal.votes, &(&1.value == 1)),
            down: Enum.count(goal.votes, &(&1.value == -1)),
            done: done,
            total: total,
            days: days,
            countdown: countdown(days),
            overdue: is_integer(days) and days < 0
          }
        end)
    }
  end

  @doc "A goal as JSON for the bots' API (or nil)."
  @spec to_json(Goal.t() | nil) :: map() | nil
  def to_json(%Goal{} = g),
    do: %{
      "id" => g.id,
      "key" => g.key,
      "title" => g.title,
      "outcome" => g.outcome,
      "target_date" => g.target_date && Date.to_iso8601(g.target_date),
      "target_label" => g.target_label
    }

  def to_json(_goal), do: nil

  defp broadcast,
    do: Phoenix.PubSub.broadcast(TalesForge.PubSub, TalesForge.Board.topic(), {:board, :changed})
end
