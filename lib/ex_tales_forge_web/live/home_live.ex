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
      <div class="mx-auto max-w-3xl space-y-8">
        <header class="space-y-2">
          <p class="text-sm font-medium uppercase tracking-wide text-amber-700">Tales Forge</p>
          <h1 class="text-3xl font-bold text-zinc-900">Your adventures await</h1>
          <p class="text-zinc-600">
            Text-first AI RPG on the BEAM. Jido agents, LiveView, and a living world in Merovingia.
          </p>
        </header>

        <div>
          <button
            phx-click="new_session"
            class="rounded-lg bg-amber-700 px-4 py-2 font-medium text-white hover:bg-amber-800"
          >
            Start new session
          </button>
        </div>

        <section :if={@sessions != []} class="space-y-3">
          <h2 class="text-lg font-semibold text-zinc-900">Recent sessions</h2>
          <ul class="divide-y divide-zinc-200 rounded-xl border border-zinc-200 bg-white">
            <li :for={session <- @sessions} class="px-4 py-3">
              <.link navigate={~p"/play/#{session.id}"} class="flex items-center justify-between">
                <span class="font-medium text-zinc-900">{session.name}</span>
                <span class="text-sm text-zinc-500">{session.status}</span>
              </.link>
            </li>
          </ul>
        </section>
      </div>
    </Layouts.app>
    """
  end
end
