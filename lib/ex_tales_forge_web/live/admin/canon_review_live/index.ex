defmodule TalesForgeWeb.AdminLive.CanonReviewLive.Index do
  @moduledoc """
  Founder tools: the list of game sessions for the session-versus-canon
  review. Each row opens the review of one session
  (`TalesForgeWeb.AdminLive.CanonReviewLive.Show`).
  """

  use TalesForgeWeb, :live_view

  import TalesForgeWeb.AdminComponents

  alias TalesForge.Admin

  @impl true
  def mount(_params, _session, socket) do
    {:ok,
     socket
     |> assign(:page_title, "Session versus canon")
     |> assign(:sessions, Admin.list_sessions())}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.admin socket={@socket} flash={@flash} active="canon_review">
      <header class="space-y-2">
        <h2 class="font-serif text-2xl font-bold text-[var(--paper-ink)]">Session versus canon</h2>
        <p class="text-sm text-[var(--paper-muted)]">
          Select a session. Then start the review to compare the session with its world seed.
        </p>
      </header>

      <.section_card title="Sessions">
        <ul id="canon-review-sessions" class="divide-y divide-[var(--paper-rule)] text-sm">
          <li :for={%{session: s} <- @sessions} class="py-2">
            <.link
              navigate={~p"/admin/founders/canon-review/#{s.id}"}
              class="text-[var(--paper-accent)]"
            >
              {s.name}
            </.link>
            <span class="text-[var(--paper-muted)]">
              · {get_in(s.world_state || %{}, ["adventure_id"]) || "—"}
            </span>
          </li>
        </ul>
      </.section_card>
    </Layouts.admin>
    """
  end
end
