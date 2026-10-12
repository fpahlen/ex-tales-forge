defmodule TalesForgeWeb.TeamWorkLogLive do
  @moduledoc """
  The founders' work log at `/team/work-log`, from the "Work log" item in
  the /team menu. All founders see the full log of all founders
  (`TalesForge.WorkLog.Report`).

  - The range form selects the days (Europe/Stockholm). The default is the
    last 30 days.
  - The table shows each auto session and each manual entry, with its work
    note, newest first. The totals show the hours of each founder.
  - The manual form adds hours, a date and a reason
    (`TalesForge.WorkLog.add_entry/2`). The founder field is the signed-in
    founder by default. For the spreadsheet import, use the reason
    "Imported from spreadsheet" and the original date.
  - The CSV link downloads one row for each founder and day
    (`TalesForgeWeb.WorkLogExportController`).

  The log counts actions, not open pages. Reading a card is not work time in v1.
  """

  use TalesForgeWeb, :live_view

  alias TalesForge.WorkLog
  alias TalesForge.WorkLog.{Entry, Report, Sessions}
  alias TalesForgeWeb.Layouts
  alias TalesForgeWeb.TeamLayout
  alias TalesForgeWeb.TimeAgo

  @default_days 30

  @impl true
  @spec mount(map(), map(), Phoenix.LiveView.Socket.t()) :: {:ok, Phoenix.LiveView.Socket.t()}
  def mount(_params, _session, socket) do
    to = Report.today()

    {:ok,
     socket
     |> assign(:page_title, "Work log")
     |> assign(:d, TalesForge.TeamPage.data())
     |> assign(:from, Date.add(to, -(@default_days - 1)))
     |> assign(:to, to)
     |> assign(:entry_form, entry_form(socket.assigns[:admin_email]))
     |> load()}
  end

  defp entry_form(founder, params \\ %{}) do
    defaults = %{
      "founder" => founder || "",
      "date" => Date.to_iso8601(Report.today()),
      "hours" => "",
      "reason" => ""
    }

    to_form(Map.merge(defaults, params), as: :entry)
  end

  defp load(socket) do
    rows = Report.rows(socket.assigns.from, socket.assigns.to)
    socket |> assign(:rows, rows) |> assign(:totals, Report.totals(rows))
  end

  @impl true
  @spec handle_event(String.t(), map(), Phoenix.LiveView.Socket.t()) ::
          {:noreply, Phoenix.LiveView.Socket.t()}
  def handle_event("range", %{"range" => %{"from" => from, "to" => to}}, socket) do
    with {:ok, from} <- Date.from_iso8601(from),
         {:ok, to} <- Date.from_iso8601(to),
         true <- Date.compare(from, to) != :gt do
      {:noreply, socket |> assign(from: from, to: to) |> load()}
    else
      _ -> {:noreply, put_flash(socket, :error, "Give a start date on or before the end date.")}
    end
  end

  def handle_event("add_entry", %{"entry" => params}, socket) do
    case WorkLog.add_entry(socket.assigns.admin_email, params) do
      {:ok, %Entry{} = entry} ->
        {:noreply,
         socket
         |> put_flash(
           :info,
           "The entry is saved: #{Report.hours(entry.minutes)} h for #{entry.founder}."
         )
         |> assign(:entry_form, entry_form(socket.assigns.admin_email))
         |> load()}

      {:error, cs} ->
        {:noreply,
         socket
         |> put_flash(:error, "Correct the entry: " <> errors(cs))
         |> assign(:entry_form, entry_form(socket.assigns.admin_email, params))}
    end
  end

  # One line with each field and its first message, for the flash.
  defp errors(%Ecto.Changeset{errors: errors}),
    do:
      errors
      |> Enum.uniq_by(&elem(&1, 0))
      |> Enum.map_join("; ", fn {f, {msg, _}} -> "#{f} #{msg}" end)

  @impl true
  @spec render(map()) :: Phoenix.LiveView.Rendered.t()
  def render(assigns) do
    assigns = assign(assigns, :idle, Sessions.idle_minutes())

    ~H"""
    <div id="team-work-log-page" class="team-page paper-themed paper-home min-h-dvh">
      <TeamLayout.header socket={assigns[:socket]} page={:presentation} items={[]} />

      <main id="work-log" class="mx-auto max-w-6xl space-y-10 px-4 pb-16 pt-8 sm:px-6 sm:pt-12">
        <header class="max-w-3xl space-y-2">
          <h1 class="font-serif text-2xl font-bold sm:text-3xl">Work log</h1>
          <p class="text-base leading-relaxed text-[var(--paper-muted)]">
            The app logs each founder action: card comments, card moves, card edits, team chat and game turns.
            A session starts at the first action. It ends at the last action when {@idle} minutes pass with no new action.
            The idle time does not count. Add work outside the app as a manual entry.
          </p>
        </header>

        <section id="work-log-range" class="space-y-3">
          <.form
            for={%{}}
            as={:range}
            id="work-log-range-form"
            phx-submit="range"
            class="flex flex-wrap items-end gap-3"
          >
            <label class="text-sm">
              From
              <input
                type="date"
                name="range[from]"
                value={Date.to_iso8601(@from)}
                class="block rounded border px-2 py-1"
              />
            </label>
            <label class="text-sm">
              To
              <input
                type="date"
                name="range[to]"
                value={Date.to_iso8601(@to)}
                class="block rounded border px-2 py-1"
              />
            </label>
            <button type="submit" class="rounded-full border px-4 py-1.5 text-sm font-semibold">Show</button>
            <a
              id="work-log-csv"
              href={
                ~p"/team/work-log.csv?#{[from: Date.to_iso8601(@from), to: Date.to_iso8601(@to)]}"
              }
              class="rounded-full border px-4 py-1.5 text-sm font-semibold"
            >
              Download CSV
            </a>
          </.form>
        </section>

        <section id="work-log-totals" aria-labelledby="work-log-totals-title" class="space-y-2">
          <h2 id="work-log-totals-title" class="font-serif text-xl font-bold">
            Hours for each founder
          </h2>
          <p :if={@totals == []} class="text-[var(--paper-muted)]">
            The log has no work in these days.
          </p>
          <ul class="space-y-1">
            <li :for={{founder, minutes} <- @totals} id={"work-log-total-#{founder}"}>
              <span class="font-semibold">{founder}</span>: {Report.hours(minutes)} h
            </li>
          </ul>
        </section>

        <section id="work-log-rows" aria-labelledby="work-log-rows-title" class="space-y-2">
          <h2 id="work-log-rows-title" class="font-serif text-xl font-bold">Sessions and entries</h2>
          <div class="overflow-x-auto">
            <table class="w-full text-left text-sm">
              <thead>
                <tr class="border-b">
                  <th class="py-1 pr-3">Date</th>
                  <th class="py-1 pr-3">Founder</th>
                  <th class="py-1 pr-3">Time (Stockholm)</th>
                  <th class="py-1 pr-3">Hours</th>
                  <th class="py-1 pr-3">Type</th>
                  <th class="py-1">Work note</th>
                </tr>
              </thead>
              <tbody>
                <tr :for={row <- @rows} class="work-log-row border-b align-top">
                  <td class="py-1 pr-3">{Date.to_iso8601(row.date)}</td>
                  <td class="py-1 pr-3">{row.founder}</td>
                  <td class="py-1 pr-3">{span(row)}</td>
                  <td class="py-1 pr-3">{Report.hours(row.minutes)}</td>
                  <td class="py-1 pr-3">{if row.source == :auto, do: "Auto", else: "Manual"}</td>
                  <td class="py-1">{row.note}</td>
                </tr>
              </tbody>
            </table>
          </div>
        </section>

        <section id="work-log-add" aria-labelledby="work-log-add-title" class="max-w-xl space-y-3">
          <h2 id="work-log-add-title" class="font-serif text-xl font-bold">Add a manual entry</h2>
          <p class="text-sm text-[var(--paper-muted)]">
            Add work outside the app, for example code, meetings or planning.
            For the spreadsheet import, write the reason "Imported from spreadsheet" and give the original date.
          </p>
          <.form for={@entry_form} id="work-log-entry-form" phx-submit="add_entry" class="space-y-2">
            <.input field={@entry_form[:founder]} type="email" label="Founder email" />
            <.input field={@entry_form[:date]} type="date" label="Date" />
            <.input
              field={@entry_form[:hours]}
              type="number"
              step="0.25"
              min="0.25"
              max="24"
              label="Hours"
            />
            <.input field={@entry_form[:reason]} type="text" label="Reason" />
            <button type="submit" class="rounded-full border px-4 py-1.5 text-sm font-semibold">Save the entry</button>
          </.form>
        </section>
      </main>

      <TeamLayout.footer d={@d} />
      <Layouts.flash_group flash={@flash} />
    </div>
    """
  end

  defp span(%{source: :auto, started_at: s, ended_at: e}), do: "#{clock(s)}–#{clock(e)}"
  defp span(_row), do: ""

  defp clock(at), do: TimeAgo.stockholm(at, "%H:%M")
end
