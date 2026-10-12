defmodule TalesForgeWeb.TeamGoals do
  @moduledoc """
  The goals strip at the top of the founders' idea board
  (`TalesForgeWeb.TeamIdeaBoard`, `TalesForge.Board.Goals`): the north star
  line with its countdown, then each goal in score order with its votes, a
  progress bar (Done cards over all its cards, archived cards not counted)
  and its time left, and the count of cards without a goal. The events go to
  the board component (`myself`).
  """
  use Phoenix.Component

  import TalesForgeWeb.CoreComponents, only: [icon: 1]

  attr :strip, :map, required: true
  attr :founder, :string, default: nil
  attr :myself, :any, required: true
  attr :downvote_for, :any, default: nil
  attr :error, :string, default: nil
  attr :can_vote, :boolean, default: true

  @spec strip(map()) :: Phoenix.LiveView.Rendered.t()
  def strip(assigns) do
    ~H"""
    <section id="board-goals" aria-labelledby="board-north-star" class="team-card grid gap-3 rounded-xl p-4">
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
          Unassigned: <span data-role="count" class="font-semibold tabular-nums">{@strip.unassigned}</span>
          {if @strip.unassigned == 1, do: "card", else: "cards"}
        </p>
      </div>
      <p :if={@error} id="board-goals-error" role="alert" class="rounded bg-red-50 px-2 py-1 text-sm text-red-800">
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
            </div>
            <div :if={@can_vote} class="flex shrink-0 items-center gap-1" role="group" aria-label={"Votes on #{row.goal.title}"}>
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
                class={["inline-flex min-h-11 min-w-11 items-center justify-center gap-1 rounded border px-2", vote_class(mine == 1, :up)]}
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
                class={["inline-flex min-h-11 min-w-11 items-center justify-center gap-1 rounded border px-2", vote_class(mine == -1, :down)]}
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
              What needs work? (necessary for a -1)
              <textarea name="reason" rows="2" required class="rounded border border-[var(--paper-rule)] bg-[var(--paper-panel)] px-2 py-1 font-normal"></textarea>
            </label>
            <div class="flex flex-wrap gap-2">
              <button type="submit" class="min-h-11 rounded border px-3 font-semibold">Save -1 and reason</button>
              <button type="button" phx-click="cancel_goal_downvote" phx-target={@myself} class="min-h-11 rounded px-3">Cancel</button>
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
              class="h-2 overflow-hidden rounded-full bg-[var(--paper-bg)]"
            >
              <div data-role="bar" class="h-full rounded-full bg-[var(--paper-accent)]" style={"width: #{percent(row.done, row.total)}%"}></div>
            </div>
            <p class="mt-1 flex flex-wrap justify-between gap-2 text-xs">
              <span data-role="progress" class="tabular-nums">{row.done} of {row.total} done</span>
              <span>
                <span :if={row.goal.target_label} class="text-[var(--paper-muted)]">{row.goal.target_label} ·</span>
                <span data-role="countdown" data-overdue={to_string(row.overdue)} class={["font-semibold", countdown_class(row.overdue)]}>
                  {row.countdown || "No target date"}
                </span>
              </span>
            </p>
          </div>
        </li>
      </ol>
    </section>
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

  defp countdown_class(true), do: "text-[var(--color-warning)] team-goal-overdue"
  defp countdown_class(_), do: "text-[var(--paper-ink)]"

  defp vote_class(true, :up),
    do: "border-[var(--paper-accent)] bg-[var(--paper-accent)] text-[var(--paper-on-accent)] font-semibold"

  defp vote_class(true, :down), do: "border-red-700 bg-red-700 text-white font-semibold"
  defp vote_class(false, _), do: "border-transparent hover:bg-[var(--paper-bg)]"
end
