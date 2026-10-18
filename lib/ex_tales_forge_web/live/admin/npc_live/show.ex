defmodule TalesForgeWeb.AdminLive.NpcLive.Show do
  @moduledoc """
  Admin: one NPC in a session (its character row), with its runtime state to edit.
  """

  use TalesForgeWeb, :live_view

  import TalesForgeWeb.AdminComponents

  alias TalesForge.Admin

  @impl true
  def mount(%{"id" => session_id, "npc_id" => npc_id}, _session, socket) do
    session = Admin.get_session!(session_id)

    # The URL carries the NPC's slug (npc_id), unique per session.
    case Admin.get_npc(session.id, npc_id) do
      nil ->
        {:ok,
         socket
         |> put_flash(:error, "No NPC #{inspect(npc_id)} in this session.")
         |> push_navigate(to: ~p"/admin/play/sessions/#{session.id}/npcs")}

      npc ->
        {:ok, assign_npc(socket, session, npc)}
    end
  end

  defp assign_npc(socket, session, npc) do
    socket
    |> assign(:page_title, npc.npc_id)
    |> assign(:session, session)
    |> assign(:npc, npc)
    |> assign(:runtime_json, Admin.encode_json(npc.runtime_state))
    |> assign(:personality_json, Admin.encode_json(npc.personality))
  end

  @impl true
  def handle_event("save_runtime", %{"runtime_json" => json}, socket) do
    %{session: session, npc: npc} = socket.assigns

    case Admin.update_npc_runtime_state(npc, json) do
      {:ok, npc} ->
        {:noreply,
         socket
         |> assign_npc(session, npc)
         |> put_flash(:info, "Runtime state saved.")}

      {:error, reason} ->
        {:noreply, put_flash(socket, :error, reason)}
    end
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.admin socket={@socket} flash={@flash} active="sessions">
      <header class="space-y-2">
        <.link
          navigate={~p"/admin/play/sessions/#{@session.id}/npcs"}
          class="text-sm text-[var(--paper-accent)]"
        >
          ← NPCs
        </.link>
        <h2 class="font-serif text-2xl font-bold text-[var(--paper-ink)]">{@npc.npc_id}</h2>
      </header>

      <.section_card title="Personality (read-only)">
        <pre class="overflow-x-auto rounded bg-[var(--paper-bg)] p-3 text-xs">{@personality_json}</pre>
        <p class="text-xs text-[var(--paper-muted)]">
          Seeded from priv/npcs at session creation. Reseed session NPCs to refresh from disk.
        </p>
      </.section_card>

      <.section_card title="Runtime state (JSON)">
        <form phx-submit="save_runtime" class="space-y-3">
          <.json_editor id="runtime_json" label="runtime_state" value={@runtime_json} rows={20} />
          <button
            type="submit"
            class="rounded bg-[var(--paper-accent)] px-4 py-2 text-sm text-[var(--paper-on-accent)]"
          >
            Save runtime state
          </button>
        </form>
      </.section_card>
    </Layouts.admin>
    """
  end
end
