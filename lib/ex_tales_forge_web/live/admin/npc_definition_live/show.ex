defmodule TalesForgeWeb.AdminLive.NpcDefinitionLive.Show do
  use TalesForgeWeb, :live_view

  import TalesForgeWeb.AdminComponents

  require Ash.Query

  alias TalesForge.Admin
  alias TalesForge.Images

  @impl true
  def mount(%{"id" => npc_id}, _session, socket) do
    json = Admin.npc_definition_json(npc_id)
    portrait_url = get_portrait_url(npc_id)

    if connected?(socket) do
      Phoenix.PubSub.subscribe(TalesForge.PubSub, "npc_definitions:#{npc_id}")
    end

    {:ok,
     socket
     |> assign(:page_title, npc_id)
     |> assign(:npc_id, npc_id)
     |> assign(:json, json)
     |> assign(:portrait_url, portrait_url)}
  end

  defp get_portrait_url(npc_id) do
    case Ash.read(TalesForge.Authoring.NpcDefinition |> Ash.Query.filter(npc_id == ^npc_id),
           load: []
         ) do
      {:ok, [%TalesForge.Authoring.NpcDefinition{} = rec | _]} -> rec.portrait_url
      _ -> nil
    end
  rescue
    _ -> nil
  end

  @impl true
  def handle_event("save", %{"definition_json" => json}, socket) do
    case Admin.save_npc_definition(socket.assigns.npc_id, json) do
      {:ok, _definition} ->
        {:noreply,
         socket
         |> assign(:json, Admin.npc_definition_json(socket.assigns.npc_id))
         |> put_flash(:info, "NPC definition saved.")}

      {:error, reason} ->
        {:noreply, put_flash(socket, :error, reason)}
    end
  end

  def handle_event("generate_portrait", _params, socket) do
    npc_id = socket.assigns.npc_id
    Images.enqueue_portrait(npc_id)

    {:noreply,
     put_flash(socket, :info, "Portrait generation enqueued. It will update live shortly.")}
  end

  @impl true
  def handle_info({:portrait_updated, url}, socket) do
    {:noreply,
     socket
     |> assign(:portrait_url, url)
     |> assign(:json, Admin.npc_definition_json(socket.assigns.npc_id))
     |> put_flash(:info, "Portrait ready!")}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.admin flash={@flash} active="npc_definitions">
      <header class="space-y-2">
        <.link navigate={~p"/admin/npc-definitions"} class="text-sm text-[var(--paper-accent)]">
          ← NPC definitions
        </.link>
        <h2 class="font-serif text-2xl font-bold text-[var(--paper-ink)]">{@npc_id}</h2>
      </header>

      <.section_card title="Portrait">
        <%= if @portrait_url && @portrait_url != "" do %>
          <img
            src={@portrait_url}
            alt={@npc_id}
            class="h-32 w-32 rounded-lg object-cover border border-[var(--paper-rule)] image-zoomable hover:ring-2 hover:ring-[var(--paper-accent)]/60 cursor-zoom-in"
            data-alt={@npc_id}
          />
          <button
            type="button"
            phx-click="generate_portrait"
            class="mt-2 rounded bg-[var(--paper-accent)] px-3 py-1 text-sm text-white"
          >
            Regenerate portrait (Grok sketch)
          </button>
        <% else %>
          <div class="h-32 w-32 rounded-lg bg-[var(--paper-margin)] flex items-center justify-center text-sm text-[var(--paper-muted)] border border-[var(--paper-rule)]">
            No portrait yet
          </div>
          <button
            type="button"
            phx-click="generate_portrait"
            class="mt-2 rounded bg-[var(--paper-accent)] px-3 py-1 text-sm text-white"
          >
            Generate portrait (Grok sketch)
          </button>
        <% end %>
      </.section_card>

      <.section_card title="Definition JSON">
        <form phx-submit="save" class="space-y-3">
          <.json_editor
            id="definition_json"
            label="priv/npcs/#{@npc_id}.json"
            value={@json}
            rows={28}
          />
          <button type="submit" class="rounded bg-[var(--paper-accent)] px-4 py-2 text-sm text-white">
            Save to disk
          </button>
        </form>
      </.section_card>
    </Layouts.admin>
    """
  end
end
