defmodule TalesForgeWeb.AdminLive.NpcLive.Show do
  @moduledoc """
  Admin: one NPC in a session (its character row), with its runtime state to edit.

  The header names the session (name and id), so the page read is the
  session played. Saving checks that the row has not changed since the
  page read it (a turn played, a trade): a stale copy is not saved; the
  page says so and shows the row as it is now.
  """

  use TalesForgeWeb, :live_view

  import TalesForgeWeb.AdminComponents
  alias TalesForge.GameCharacter.Rows

  alias TalesForge.Admin

  @stale "Not saved: this NPC changed after the page loaded (a turn was played). " <>
           "The page now shows the current state; make your edit again."

  @impl true
  def mount(%{"id" => session_id, "npc_id" => npc_id}, _session, socket) do
    session = Admin.get_session!(session_id)

    # The URL carries the NPC's slug (npc_id), unique per session.
    case Rows.get(session.id, npc_id) do
      nil ->
        {:ok,
         socket
         |> put_flash(:error, "No NPC #{inspect(npc_id)} in this session.")
         |> push_navigate(to: ~p"/admin/play/sessions/#{session.id}/npcs")}

      npc ->
        {:ok, socket |> assign(:session, session) |> assign_npc(npc)}
    end
  end

  defp assign_npc(socket, npc) do
    assign(socket,
      page_title: npc.npc_id,
      npc: npc,
      runtime_json: Admin.encode_json(npc.runtime_state),
      personality_json: Admin.encode_json(npc.personality)
    )
  end

  @impl true
  def handle_event("save_runtime", %{"runtime_json" => json}, socket),
    do: {:noreply, saved(socket, Admin.update_npc_runtime_state(socket.assigns.npc, json))}

  defp saved(socket, {:ok, npc}),
    do: socket |> assign_npc(npc) |> put_flash(:info, "Runtime state saved.")

  # A stale copy: show the row as it is now.
  defp saved(%{assigns: %{session: session, npc: npc}} = socket, {:error, :stale}),
    do: socket |> assign_npc(Rows.get(session.id, npc.npc_id)) |> put_flash(:error, @stale)

  defp saved(socket, {:error, reason}), do: put_flash(socket, :error, reason)

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
        <p id="npc-session" class="text-sm text-[var(--paper-ink)]">
          Session <span class="font-semibold">{@session.name}</span>
          <span class="font-mono">{@session.id}</span>
        </p>
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
