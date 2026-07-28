defmodule TalesForgeWeb.AdminLive.NpcDefinitionLive.Index do
  use TalesForgeWeb, :live_view

  alias TalesForge.Admin

  @impl true
  def mount(_params, _session, socket) do
    {:ok,
     socket
     |> assign(:page_title, "NPC definitions")
     |> assign(:definitions, Admin.list_npc_definitions())}
  end

  # Note: portrait generation can be triggered from the detail page.
  # After generation (async), reload the page to see the portrait here.

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.admin flash={@flash} active="npc_definitions">
      <header class="space-y-1">
        <h2 class="font-serif text-2xl font-bold text-[var(--paper-ink)]">NPC definitions</h2>
        <p class="text-sm text-[var(--paper-muted)]">
          Authored files in priv/npcs. Changes apply to new sessions unless you reseed NPC instances.
        </p>
      </header>

      <div class="overflow-x-auto rounded-lg border border-[var(--paper-rule)]">
        <table class="min-w-full divide-y divide-[var(--paper-rule)] text-sm">
          <thead class="bg-[var(--paper-panel)] text-left text-[var(--paper-muted)]">
            <tr>
              <th class="px-4 py-2">Portrait</th>
              <th class="px-4 py-2">ID</th>
              <th class="px-4 py-2">Name</th>
              <th class="px-4 py-2">Role</th>
              <th class="px-4 py-2">Default location</th>
              <th class="px-4 py-2"></th>
            </tr>
          </thead>
          <tbody class="divide-y divide-[var(--paper-rule)]">
            <tr :for={npc <- @definitions}>
              <td class="px-4 py-3">
                <%= if Map.get(npc, :portrait_url) do %>
                  <img
                    src={Map.get(npc, :portrait_url)}
                    alt={Map.get(npc, :name)}
                    class="h-10 w-10 rounded-full object-cover border border-[var(--paper-rule)] image-zoomable hover:ring-1 hover:ring-[var(--paper-accent)]/60 cursor-zoom-in"
                    data-alt={Map.get(npc, :name)}
                  />
                <% else %>
                  <div class="h-10 w-10 rounded-full bg-[var(--paper-margin)] flex items-center justify-center text-xs font-semibold uppercase text-[var(--paper-muted)] border border-[var(--paper-rule)]">
                    {String.first(Map.get(npc, :name) || "?") || "?"}
                  </div>
                <% end %>
              </td>
              <td class="px-4 py-3 font-mono">{Map.get(npc, :id)}</td>
              <td class="px-4 py-3">{Map.get(npc, :name)}</td>
              <td class="px-4 py-3">{Map.get(npc, :role)}</td>
              <td class="px-4 py-3">{Map.get(npc, :default_location_id)}</td>
              <td class="px-4 py-3">
                <.link
                  navigate={~p"/admin/npc-definitions/#{Map.get(npc, :id)}"}
                  class="text-[var(--paper-accent)]"
                >
                  Edit JSON
                </.link>
              </td>
            </tr>
          </tbody>
        </table>
      </div>
    </Layouts.admin>
    """
  end
end
