defmodule TalesForgeWeb.HomeLive do
  use TalesForgeWeb, :live_view

  alias TalesForge.GameSessions

  @impl true
  def mount(_params, _session, socket) do
    {:ok,
     socket
     |> assign(:page_title, "Tales Forge")
     |> assign(:sessions, GameSessions.list_sessions())}
  end

  @impl true
  def handle_event("new_session", _params, socket) do
    case GameSessions.create_session(%{name: "Crossroads Hamlet"}) do
      {:ok, session} ->
        {:noreply, push_navigate(socket, to: ~p"/play/#{session.id}")}

      {:error, _changeset} ->
        {:noreply, put_flash(socket, :error, "Could not start a new session.")}
    end
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash}>
      <header class="space-y-2">
        <p class="play-label text-[var(--paper-accent)]">Tales Forge</p>
        <h1 class="font-serif text-3xl font-bold text-[var(--paper-ink)]">Your adventures await</h1>
        <p class="text-[var(--paper-muted)]">
          Text-first AI RPG on the BEAM. Jido agents, LiveView, and a living world in Merovingia.
        </p>
      </header>

      <div>
        <button
          phx-click="new_session"
          class="rounded bg-[var(--paper-accent)] px-4 py-2 font-medium text-white hover:opacity-90"
        >
          Start new session
        </button>
      </div>

      <section :if={@sessions != []} class="space-y-3">
        <h2 class="play-label">Recent sessions</h2>
        <ul class="divide-y divide-[var(--paper-rule)] rounded-lg border border-[var(--paper-rule)] bg-[var(--paper-panel)]">
          <li :for={session <- @sessions} class="px-4 py-3">
            <.link
              navigate={~p"/play/#{session.id}"}
              class="flex items-center justify-between hover:opacity-80"
            >
              <span class="font-medium text-[var(--paper-ink)]">{session.name}</span>
              <span class="text-sm text-[var(--paper-muted)]">{session.status}</span>
            </.link>
          </li>
        </ul>
      </section>
    </Layouts.app>
    """
  end
end
