defmodule TalesForgeWeb.TeamWhatWeDid do
  @moduledoc """
  The "What have we done" panel of the founders' page (`/team`), rendered by
  `TalesForgeWeb.TeamWhatWeDidLive` from a `t:TalesForge.PrFeed.WhatWeDid.t/0`:
  short theme bullets of the pull requests merged in the last days, each with
  links to its pull requests. With `:titles` (no model answer) the bullets are
  the plain titles.
  """

  use Phoenix.Component

  @doc "The panel."
  attr :summary, :map, required: true, doc: "a `t:TalesForge.PrFeed.WhatWeDid.t/0`"
  attr :loading, :boolean, default: false, doc: "true while the bullets are made"

  @spec panel(map()) :: Phoenix.LiveView.Rendered.t()
  def panel(assigns) do
    ~H"""
    <div
      id="what-we-did"
      class="team-card space-y-3 p-4 sm:p-5"
      data-source={@summary.source}
      data-count={@summary.count}
    >
      <p :if={@summary.count == 0} id="what-we-did-empty" class="text-[var(--paper-muted)]">
        No merged pull requests since {Calendar.strftime(@summary.since, "%-d %b")}.
      </p>
      <ul :if={@summary.count > 0} id="what-we-did-bullets" class="list-disc space-y-2 pl-5">
        <li :for={bullet <- @summary.bullets} class="leading-relaxed">
          {bullet.text}
          <span class="text-sm text-[var(--paper-muted)]">
            (<%= for {pr, i} <- Enum.with_index(bullet.prs) do %>
              <%= if i > 0 do %>
                ,
              <% end %>
              <a
                href={pr.url}
                target="_blank"
                rel="noopener"
                class="underline"
                data-pr={pr.number}
              >#{pr.number}</a>
            <% end %>)
          </span>
        </li>
      </ul>
      <p :if={@summary.count > 0} class="text-sm text-[var(--paper-muted)]">
        {@summary.count} merged pull {if @summary.count == 1, do: "request", else: "requests"} since {Calendar.strftime(
          @summary.since,
          "%-d %b"
        )} (Stockholm time).
        <span :if={@summary.source == :titles and @summary.count > 0} id="what-we-did-titles">
          The list shows the pull request titles.
        </span>
        <span :if={@loading} id="what-we-did-loading">The short summary is on its way.</span>
      </p>
    </div>
    """
  end
end
