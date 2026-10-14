defmodule TalesForgeWeb.TeamUpcoming do
  @moduledoc """
  The Upcoming panel of the team page (`/team`): the scheduled jobs of the
  team config with the next time, the owner (a person, a bot or code) and the
  result of the last run (`TalesForge.Board.Schedule.rows/3`). Rendered by
  `TalesForgeWeb.TeamUpcomingLive`.

  The server sends each time in UTC (`<time datetime>`, with a UTC text). The
  colocated `.LocalTime` hook writes the time again in the viewer's local
  time zone. The server has no time zone database.
  """

  use Phoenix.Component

  alias TalesForge.Board.Schedule

  @doc "The panel: one row for each job, in the order of the team config."
  attr :rows, :list, required: true, doc: "`t:TalesForge.Board.Schedule.row/0` items"

  @spec panel(map()) :: Phoenix.LiveView.Rendered.t()
  def panel(assigns) do
    ~H"""
    <div id="upcoming-panel" class="space-y-3">
      <p :if={@rows == []} id="upcoming-empty" class="team-callout p-4 text-sm">
        No jobs are scheduled.
      </p>
      <ol :if={@rows != []} id="upcoming-list" class="team-card divide-y divide-[var(--paper-line)]">
        <li
          :for={row <- @rows}
          id={"upcoming-" <> row.id}
          class="flex flex-wrap items-baseline gap-x-4 gap-y-1 p-3"
          data-job={row.id}
          data-owner-kind={if row.code?, do: "code", else: "person"}
        >
          <.local_time
            id={"upcoming-next-" <> row.id}
            at={row.next_at}
            class="min-w-[7.5rem] font-mono text-sm font-semibold"
          />
          <span class="flex-1 font-semibold">{row.name}</span>
          <span class="text-sm text-[var(--paper-muted)]" data-role="owner">{row.owner}</span>
          <.last_result id={row.id} run={row.last} />
        </li>
      </ol>
      <p class="text-xs text-[var(--paper-muted)]">
        Times are in your local time zone. "Code" jobs run with no bot.
      </p>
      <script :type={Phoenix.LiveView.ColocatedHook} name=".LocalTime">
        export default {
          mounted() { this.show() },
          updated() { this.show() },
          show() {
            const at = new Date(this.el.getAttribute("datetime"))
            if (isNaN(at)) return
            const now = new Date()
            const sameDay = at.toDateString() === now.toDateString()
            const opts = sameDay
              ? {hour: "2-digit", minute: "2-digit"}
              : {weekday: "short", day: "numeric", month: "short", hour: "2-digit", minute: "2-digit"}
            this.el.textContent = new Intl.DateTimeFormat(undefined, opts).format(at)
            this.el.title = at.toISOString()
          }
        }
      </script>
    </div>
    """
  end

  attr :id, :string, required: true
  attr :run, :any, required: true

  defp last_result(%{run: nil} = assigns) do
    ~H"""
    <span id={"upcoming-last-" <> @id} class="text-sm text-[var(--paper-muted)]" data-status="none">
      No run yet
    </span>
    """
  end

  defp last_result(assigns) do
    ~H"""
    <span
      id={"upcoming-last-" <> @id}
      class={["text-sm font-semibold", status_class(@run.status)]}
      data-status={@run.status}
    >
      {label(@run.status)}
      <.local_time
        id={"upcoming-last-at-" <> @id}
        at={@run.finished_at || @run.started_at}
        class="font-normal text-[var(--paper-muted)]"
      />
    </span>
    """
  end

  attr :id, :string, required: true
  attr :at, DateTime, required: true
  attr :class, :string, default: nil

  defp local_time(assigns) do
    ~H"""
    <time id={@id} datetime={DateTime.to_iso8601(@at)} phx-hook=".LocalTime" class={@class}>
      {utc_text(@at)}
    </time>
    """
  end

  @doc """
  The status label of a run.

      iex> Enum.map(~w(open ok failed no_report), &TalesForgeWeb.TeamUpcoming.label/1)
      ["Open", "OK", "Failed", "No report"]
  """
  @spec label(String.t()) :: String.t()
  def label("open"), do: "Open"
  def label("ok"), do: "OK"
  def label("failed"), do: "Failed"
  def label("no_report"), do: "No report"
  def label(other), do: other

  defp status_class("ok"), do: "text-emerald-700"
  defp status_class(s) when s in ~w(failed no_report), do: "text-red-700"
  defp status_class(_), do: "text-[var(--paper-accent)]"

  @doc """
  The UTC text of a time, until the browser writes the local time.

      iex> TalesForgeWeb.TeamUpcoming.utc_text(~U[2026-10-16 07:15:00Z])
      "2026-10-16 07:15 UTC"
  """
  @spec utc_text(DateTime.t()) :: String.t()
  def utc_text(%DateTime{} = at), do: Calendar.strftime(at, "%Y-%m-%d %H:%M UTC")

  @doc "The rows for `now` (UTC) from the team config and the stored runs."
  @spec rows(Workflow.Team.t(), DateTime.t()) :: [Schedule.row()]
  def rows(team, now), do: Schedule.rows(team, now, Schedule.last_runs())
end
