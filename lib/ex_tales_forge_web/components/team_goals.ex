defmodule TalesForgeWeb.TeamGoals do
  @moduledoc """
  The goals strip at the top of the founders' idea board
  (`TalesForgeWeb.TeamIdeaBoard`, `TalesForge.Board.Goals`): the north star
  line with its countdown, then each goal in score order with its votes, a
  progress bar (Done cards over all its cards, archived cards not counted)
  and its time left, and the count of cards without a goal. The events go to
  the board component (`myself`).

  Each goal opens and closes (`goal_toggle`). An open goal lists its cards
  that are not Done, with the title and column of each card. A founder adds
  a card without a goal, removes a card from the goal, or creates a new Idea
  card with the goal set. The QA session sees the list but gets no controls.
  On a phone the open goal is a full-screen sheet, and the page behind it
  stays locked (the `.GoalSheetScrollLock` hook sets `team-sheet-open` on
  the body). "Show cards" stays disabled until the LiveView connects
  (`connected`), so a click always reaches the board component.
  """
  use Phoenix.Component

  import TalesForgeWeb.CoreComponents, only: [icon: 1]

  attr :strip, :map, required: true
  attr :team, Workflow.Team, required: true, doc: "the team config (`Workflow.Team`)"
  attr :founder, :string, default: nil
  attr :myself, :any, required: true
  attr :downvote_for, :any, default: nil
  attr :error, :string, default: nil
  attr :can_vote, :boolean, default: true
  attr :open_id, :string, default: nil
  attr :open_cards, :map, default: nil
  attr :connected, :boolean, default: false

  @spec strip(map()) :: Phoenix.LiveView.Rendered.t()
  def strip(assigns) do
    ~H"""
    <section
      id="board-goals"
      aria-labelledby="board-north-star"
      class="team-card grid gap-3 rounded-xl p-4"
    >
      <p id="board-north-star" class="flex flex-wrap items-baseline gap-x-2 gap-y-1">
        <span class="text-xs font-semibold uppercase tracking-wide text-[var(--paper-muted)]">North star</span>
        <span class="font-serif text-lg font-semibold">{@strip.north_star.text}</span>
        <span class="text-sm text-[var(--paper-muted)]">{@strip.north_star.target_label}</span>
        <span
          id="board-north-star-countdown"
          data-overdue={to_string(@strip.north_star.days < 0)}
          class={["text-sm font-semibold", countdown_class(@strip.north_star.days < 0)]}
        >
          {@strip.north_star.countdown}
        </span>
      </p>
      <div class="flex flex-wrap items-baseline justify-between gap-2">
        <h3 class="text-sm font-semibold">Goals</h3>
        <p id="board-goals-unassigned" class="text-xs text-[var(--paper-muted)]">
          Unassigned:
          <span data-role="count" class="font-semibold tabular-nums">{@strip.unassigned}</span>
          {if @strip.unassigned == 1, do: "card", else: "cards"}
        </p>
      </div>
      <p
        :if={@error}
        id="board-goals-error"
        role="alert"
        class="rounded bg-red-50 px-2 py-1 text-sm text-red-800"
      >
        {@error}
      </p>
      <p :if={@strip.goals == []} class="text-sm text-[var(--paper-muted)]">No goals yet.</p>
      <ol id="board-goals-list" class="grid gap-2 sm:grid-cols-2 lg:grid-cols-3">
        <li
          :for={row <- @strip.goals}
          id={"goal-#{row.goal.id}"}
          data-key={row.goal.key}
          data-score={row.score}
          class="grid gap-2 rounded-lg border border-[var(--paper-rule)] bg-[var(--paper-panel)] p-3"
        >
          <div class="flex items-start justify-between gap-2">
            <div class="min-w-0">
              <p class="font-semibold">
                <span class="text-xs text-[var(--paper-muted)]">{row.goal.key}</span> {row.goal.title}
              </p>
              <p class="text-xs text-[var(--paper-muted)]">{row.goal.outcome}</p>
              <p data-role="score" class="text-xs">
                Score: <span class="font-semibold tabular-nums">{format_score(row.score)}</span>
              </p>
              <button
                type="button"
                id={"goal-#{row.goal.id}-toggle"}
                phx-click="goal_toggle"
                phx-value-goal_id={row.goal.id}
                phx-target={@myself}
                disabled={!@connected}
                aria-expanded={to_string(@open_id == row.goal.id)}
                aria-controls={"goal-#{row.goal.id}-cards"}
                class="mt-1 inline-flex min-h-11 items-center gap-1 rounded px-2 text-sm font-semibold underline disabled:cursor-wait disabled:opacity-50"
              >
                <.icon
                  name={if @open_id == row.goal.id, do: "hero-chevron-up", else: "hero-chevron-down"}
                  class="size-4"
                />
                {if @open_id == row.goal.id, do: "Close cards", else: "Show cards"}
              </button>
            </div>
            <div
              :if={@can_vote}
              class="flex shrink-0 items-center gap-1"
              role="group"
              aria-label={"Votes on #{row.goal.title}"}
            >
              <% mine = TalesForge.Board.Goals.vote_of(row.goal, @founder) %>
              <button
                type="button"
                id={"goal-#{row.goal.id}-up"}
                phx-click="goal_vote"
                phx-value-goal_id={row.goal.id}
                phx-value-vote="1"
                phx-target={@myself}
                aria-pressed={to_string(mine == 1)}
                aria-label={"Upvote: #{row.up}"}
                class={[
                  "inline-flex min-h-11 min-w-11 items-center justify-center gap-1 rounded border px-2",
                  vote_class(mine == 1, :up)
                ]}
              >
                <.icon name="hero-hand-thumb-up" class="size-5" />
                <span data-role="up" aria-hidden="true" class="tabular-nums">{row.up}</span>
              </button>
              <button
                type="button"
                id={"goal-#{row.goal.id}-down"}
                phx-click="goal_vote"
                phx-value-goal_id={row.goal.id}
                phx-value-vote="-1"
                phx-target={@myself}
                aria-pressed={to_string(mine == -1)}
                aria-label={"Downvote: #{row.down}"}
                class={[
                  "inline-flex min-h-11 min-w-11 items-center justify-center gap-1 rounded border px-2",
                  vote_class(mine == -1, :down)
                ]}
              >
                <.icon name="hero-hand-thumb-down" class="size-5" />
                <span data-role="down" aria-hidden="true" class="tabular-nums">{row.down}</span>
              </button>
            </div>
          </div>
          <form
            :if={@downvote_for == row.goal.id}
            id={"goal-#{row.goal.id}-downvote"}
            phx-submit="goal_downvote"
            phx-target={@myself}
            class="grid gap-1 rounded-lg border-2 border-warning p-2 text-sm"
          >
            <input type="hidden" name="goal_id" value={row.goal.id} />
            <label class="grid gap-1 font-semibold">
              What needs work? (necessary for a -1) <textarea
                name="reason"
                rows="2"
                required
                class="rounded border border-[var(--paper-rule)] bg-[var(--paper-panel)] px-2 py-1 font-normal"
              ></textarea>
            </label>
            <div class="flex flex-wrap gap-2">
              <button type="submit" class="min-h-11 rounded border px-3 font-semibold">Save -1 and reason</button>
              <button
                type="button"
                phx-click="cancel_goal_downvote"
                phx-target={@myself}
                class="min-h-11 rounded px-3"
              >Cancel</button>
            </div>
          </form>
          <div>
            <div
              role="progressbar"
              aria-label={"Done cards for #{row.goal.title}"}
              aria-valuemin="0"
              aria-valuemax={row.total}
              aria-valuenow={row.done}
              aria-valuetext={"#{row.done} of #{row.total} cards done"}
              class="h-2 overflow-hidden rounded-full bg-[var(--paper-rule)]"
            >
              <div
                data-role="bar"
                class="h-full rounded-full bg-[var(--paper-accent)]"
                style={"width: #{percent(row.done, row.total)}%"}
              >
              </div>
            </div>
            <p class="mt-1 flex flex-wrap justify-between gap-2 text-xs">
              <span data-role="progress" class="tabular-nums">{row.done} of {row.total} done</span>
              <span>
                <span :if={row.goal.target_label} class="text-[var(--paper-muted)]">{row.goal.target_label} ·</span>
                <span
                  data-role="countdown"
                  data-overdue={to_string(row.overdue)}
                  class={["font-semibold", countdown_class(row.overdue)]}
                >
                  {row.countdown || "No target date"}
                </span>
              </span>
            </p>
          </div>
          <.goal_cards
            :if={@open_id == row.goal.id and @open_cards != nil}
            team={@team}
            row={row}
            cards={@open_cards}
            can_edit={@can_vote}
            error={@error}
            myself={@myself}
          />
        </li>
      </ol>
    </section>
    """
  end

  attr :row, :map, required: true
  attr :team, Workflow.Team, required: true
  attr :cards, :map, required: true
  attr :can_edit, :boolean, required: true
  attr :error, :string, default: nil
  attr :myself, :any, required: true

  # The open goal: a full-screen sheet on a phone, a panel in the goal from
  # the sm breakpoint.
  defp goal_cards(assigns) do
    ~H"""
    <section
      id={"goal-#{@row.goal.id}-cards"}
      phx-hook=".GoalSheetScrollLock"
      role="region"
      aria-labelledby={"goal-#{@row.goal.id}-cards-title"}
      class="fixed inset-0 z-50 grid content-start gap-3 overflow-y-auto bg-[var(--paper-panel)] p-4 sm:static sm:z-auto sm:overflow-visible sm:border-t sm:border-[var(--paper-rule)] sm:p-0 sm:pt-2"
    >
      <div class="flex items-start justify-between gap-2">
        <h4 id={"goal-#{@row.goal.id}-cards-title"} class="font-semibold">
          Cards for {@row.goal.key} {@row.goal.title}
        </h4>
        <button
          type="button"
          id={"goal-#{@row.goal.id}-close"}
          phx-click="goal_toggle"
          phx-value-goal_id={@row.goal.id}
          phx-target={@myself}
          aria-label={"Close the cards for #{@row.goal.title}"}
          class="inline-flex min-h-11 min-w-11 items-center justify-center rounded sm:hidden"
        >
          <.icon name="hero-x-mark" class="size-6" />
        </button>
      </div>
      <p data-role="sheet-progress" class="text-xs tabular-nums sm:hidden">
        {@row.done} of {@row.total} done
      </p>
      <p :if={@error} role="alert" class="rounded bg-red-50 px-2 py-1 text-sm text-red-800 sm:hidden">
        {@error}
      </p>
      <p :if={@cards.cards == []} data-role="empty" class="text-sm text-[var(--paper-muted)]">
        This goal has no open cards.
      </p>
      <ul :if={@cards.cards != []} class="grid gap-1">
        <li
          :for={card <- @cards.cards}
          id={"goal-#{@row.goal.id}-card-#{card.id}"}
          data-column={card.column}
          class="flex items-center justify-between gap-2 rounded border border-[var(--paper-rule)] px-2 py-1"
        >
          <span class="min-w-0">
            <span class="block break-words text-sm">{card.title}</span>
            <span data-role="column" class="text-xs text-[var(--paper-muted)]">
              {TalesForge.Board.Transitions.label(@team, card.column)}
            </span>
          </span>
          <button
            :if={@can_edit}
            type="button"
            id={"goal-#{@row.goal.id}-remove-#{card.id}"}
            phx-click="goal_remove_card"
            phx-value-card_id={card.id}
            phx-target={@myself}
            aria-label={"Remove #{card.title} from the goal"}
            class="inline-flex min-h-11 min-w-11 shrink-0 items-center justify-center rounded hover:bg-[var(--paper-bg)]"
          >
            <.icon name="hero-minus-circle" class="size-5" />
          </button>
        </li>
      </ul>
      <form
        :if={@can_edit and @cards.unassigned != []}
        id={"goal-#{@row.goal.id}-add"}
        phx-submit="goal_add_card"
        phx-target={@myself}
        class="flex flex-wrap items-end gap-2"
      >
        <input type="hidden" name="goal_id" value={@row.goal.id} />
        <label class="grid flex-1 gap-1 text-sm">
          Add a card without a goal
          <select name="card_id" class="select select-sm min-h-11 w-full bg-[var(--paper-panel)]">
            <option value="">Select a card</option>
            <option :for={card <- @cards.unassigned} value={card.id}>
              {card.title} ({TalesForge.Board.Transitions.label(@team, card.column)})
            </option>
          </select>
        </label>
        <button type="submit" class="min-h-11 rounded border px-3 font-semibold">Add</button>
      </form>
      <form
        :if={@can_edit}
        id={"goal-#{@row.goal.id}-new"}
        phx-submit="goal_new_card"
        phx-target={@myself}
        class="flex flex-wrap items-end gap-2"
      >
        <input type="hidden" name="goal_id" value={@row.goal.id} />
        <label class="grid flex-1 gap-1 text-sm">
          New Idea card for this goal
          <input
            type="text"
            name="title"
            required
            maxlength="200"
            class="min-h-11 rounded border border-[var(--paper-rule)] bg-[var(--paper-panel)] px-2"
          />
        </label>
        <button type="submit" class="min-h-11 rounded border px-3 font-semibold">Create</button>
      </form>
    </section>
    <script :type={Phoenix.LiveView.ColocatedHook} name=".GoalSheetScrollLock">
      export default {
        mounted() { document.body.classList.add("team-sheet-open") },
        destroyed() { document.body.classList.remove("team-sheet-open") }
      }
    </script>
    """
  end

  @doc """
  The width of the progress bar, in percent (0 for a goal without cards).

      iex> TalesForgeWeb.TeamGoals.percent(1, 4)
      25
      iex> TalesForgeWeb.TeamGoals.percent(0, 0)
      0
  """
  @spec percent(non_neg_integer(), non_neg_integer()) :: non_neg_integer()
  def percent(_done, 0), do: 0
  def percent(done, total), do: round(done * 100 / total)

  @doc """
  The net score as shown on a goal (a plus sign on a positive score).

      iex> TalesForgeWeb.TeamGoals.format_score(2)
      "+2"
      iex> TalesForgeWeb.TeamGoals.format_score(0)
      "0"
      iex> TalesForgeWeb.TeamGoals.format_score(-1)
      "-1"
  """
  @spec format_score(integer()) :: String.t()
  def format_score(n) when n > 0, do: "+#{n}"
  def format_score(n), do: Integer.to_string(n)

  defp countdown_class(true), do: "text-[var(--color-warning)] team-goal-overdue"
  defp countdown_class(_), do: "text-[var(--paper-ink)]"

  defp vote_class(true, :up),
    do:
      "border-[var(--paper-accent)] bg-[var(--paper-accent)] text-[var(--paper-on-accent)] font-semibold"

  defp vote_class(true, :down), do: "border-red-700 bg-red-700 text-white font-semibold"
  defp vote_class(false, _), do: "border-transparent hover:bg-[var(--paper-bg)]"
end
