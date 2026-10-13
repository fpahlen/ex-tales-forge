defmodule TalesForgeWeb.TeamPie do
  @moduledoc """
  The Slicing Pie on the work-log page: an SVG pie and a table. The slices
  come from `Workflow.SlicingPie.slices/2`. This component only shows them.
  """

  use Phoenix.Component

  attr :slices, :list, required: true

  @doc "The pie chart and the table with the hours and the percentage."
  @spec pie(map()) :: Phoenix.LiveView.Rendered.t()
  def pie(assigns) do
    ~H"""
    <section id="work-log-pie" aria-labelledby="work-log-pie-title" class="space-y-3">
      <h2 id="work-log-pie-title" class="font-serif text-xl font-bold">Slicing Pie (hours)</h2>
      <p class="text-sm text-[var(--paper-muted)]">
        The pie shows the logged hours of all time. It is not the final equity split.
      </p>
      <p :if={@slices == []} id="work-log-pie-empty" class="text-[var(--paper-muted)]">
        The log has no hours yet.
      </p>
      <div :if={@slices != []} class="flex flex-wrap items-start gap-6">
        <svg viewBox="0 0 100 100" class="h-48 w-48" role="img" aria-label="Slicing Pie of hours">
          <path :for={s <- @slices} d={s.path} fill={s.color} stroke="white" stroke-width="0.5">
            <title>{s.label}: {s.hours} h, {s.percent}%</title>
          </path>
        </svg>
        <table class="text-left text-sm">
          <thead>
            <tr class="border-b">
              <th class="py-1 pr-3">Contributor</th>
              <th class="py-1 pr-3">Hours</th>
              <th class="py-1">Percentage</th>
            </tr>
          </thead>
          <tbody>
            <tr :for={s <- @slices} id={"work-log-pie-#{s.contributor}"} class="border-b">
              <td class="py-1 pr-3">
                <span class="inline-block h-3 w-3 rounded-sm" style={"background: #{s.color}"}></span>
                {s.label}
              </td>
              <td class="py-1 pr-3">{s.hours}</td>
              <td class="py-1">{s.percent}%</td>
            </tr>
          </tbody>
        </table>
      </div>
    </section>
    """
  end
end
