defmodule TalesForgeWeb.PlayLive do
  @moduledoc """
  The play page for one game session: shows the scene and turns, takes the player's action and follows turn progress over PubSub.
  """

  use TalesForgeWeb, :live_view

  import TalesForgeWeb.PlayComponents

  alias TalesForge.GameCharacter.Store
  alias TalesForge.GameSessions
  alias TalesForge.PubSub.GameSession, as: SessionPubSub
  alias TalesForge.Repo
  alias TalesForgeWeb.PlayLive.GmReveal

  @impl true
  def mount(%{"id" => id}, _session, socket) do
    if connected?(socket) do
      SessionPubSub.subscribe(id)
    end

    session =
      id
      |> GameSessions.get_session!()
      |> Repo.preload([:turns, :scenes])

    {:ok, _} = GameSessions.ensure_scene(session)

    status = GameSessions.scene_status(id)
    entries = GameSessions.transcript(session)

    {:ok,
     socket
     |> assign(:page_title, session.name)
     |> assign(:session, session)
     |> assign(:cast, Store.cast(session.id))
     |> assign(:connected, connected?(socket))
     |> assign(:thinking, false)
     |> assign(:gm_reveal, GmReveal.from_config())
     |> assign(:scene_loading, status.needs_scene)
     |> assign(:scene_image_url, current_scene_image(session))
     |> assign(:clarification, GameSessions.pending_clarification(session.world_state))
     |> assign(:llm_source, "mock")
     |> stream(:entries, entries, reset: true)}
  end

  @impl true
  def handle_event("send_message", %{"message" => message}, socket) do
    submit_action(socket, message, [])
  end

  # A picked option plays the player's words from when the question was asked
  # (stored with the pending clarification), not whatever is in the input box:
  # the form has no phx-change, so the server never sees the box anyway.
  def handle_event("pick_clarification", %{"option_id" => option_id}, socket) do
    case socket.assigns.clarification do
      %{"clarification_id" => clarification_id} ->
        submit_action(socket, "", clarification_id: clarification_id, option_id: option_id)

      _ ->
        {:noreply, socket}
    end
  end

  @impl true
  def handle_info({:scene_processing, _}, socket) do
    {:noreply, assign(socket, :scene_loading, true)}
  end

  def handle_info({:scene_completed, payload}, socket) do
    session =
      socket.assigns.session
      |> Map.put(:world_state, payload.world_state)
      |> refresh_scenes()

    {:noreply,
     socket
     |> assign(:scene_loading, false)
     |> assign(:session, session)
     |> assign(:cast, Store.cast(session.id))
     |> assign(:llm_source, payload.llm_source)
     |> assign(:scene_image_url, payload.image_url)
     |> append_entries(payload.entries)}
  end

  def handle_info({:scene_failed, {:spend_cap, kind}}, socket) do
    {:noreply,
     socket
     |> assign(:scene_loading, false)
     |> put_flash(:info, spend_cap_message(kind))}
  end

  def handle_info({:scene_failed, reason}, socket) do
    {:noreply,
     socket
     |> assign(:scene_loading, false)
     |> put_flash(:error, "Scene failed: #{reason}")}
  end

  def handle_info({:turn_processing, _}, socket) do
    {:noreply, assign(socket, :thinking, true)}
  end

  # The GM narration while it streams goes to the `.GmReveal` hook, which paces
  # it on the client (docs/design-gm-streaming.md). Each event has the whole
  # text so far, so a lost or doubled event does no harm. :reset (before a
  # JSON retry) sends empty text: the hook clears it and shows the dots.
  def handle_info({:turn_stream, {:text, text}}, socket) do
    {:noreply, socket |> assign(:thinking, true) |> push_event("gm_text", %{text: text})}
  end

  def handle_info({:turn_stream, :reset}, socket) do
    {:noreply, push_event(socket, "gm_text", %{text: ""})}
  end

  def handle_info({:clarification_needed, clarification}, socket) do
    {:noreply,
     socket
     |> assign(:thinking, false)
     |> drop_pending_action()
     |> assign(:clarification, clarification)}
  end

  def handle_info({:turn_completed, payload}, socket) do
    session =
      socket.assigns.session
      |> Map.put(:world_state, payload.world_state)
      |> Map.put(:status, Map.get(payload, :session_status, socket.assigns.session.status))

    socket =
      socket
      |> assign(:thinking, false)
      |> drop_pending_action()
      |> assign(:clarification, nil)
      |> assign(:session, session)
      |> assign(:cast, Store.cast(session.id))
      |> assign(:llm_source, payload.llm_source)
      |> append_entries(payload.entries)
      |> maybe_start_scene_after_travel(payload, session)

    {:noreply, socket}
  end

  def handle_info({:turn_failed, {:spend_cap, kind}}, socket) do
    {:noreply,
     socket
     |> assign(:thinking, false)
     |> drop_pending_action()
     |> put_flash(:info, spend_cap_message(kind))}
  end

  def handle_info({:turn_failed, reason}, socket) do
    {:noreply,
     socket
     |> assign(:thinking, false)
     |> drop_pending_action()
     |> put_flash(:error, "Turn failed: #{reason}")}
  end

  def handle_info({:npc_initiative, payload}, socket) do
    entry = %{
      id: "npc-initiative-#{payload.npc_id}-#{payload.world_tick}",
      role: "npc",
      npc_name: payload.npc_name,
      text: payload.text
    }

    {:noreply, append_entries(socket, [entry])}
  end

  @impl true
  def render(assigns) do
    world = assigns.session.world_state || %{}
    character = Map.get(world, "character", %{})

    assigns =
      assigns
      |> assign(:location_name, Map.get(world, "location_name", "Unknown"))
      |> assign(:world_clock, Map.get(world, "world_clock", "—"))
      |> assign(:character, character)
      |> assign(:present_npcs, present_npcs(world, assigns.cast))
      |> assign(:last_exchange, last_exchange(world))
      |> assign(:quick_stats, quick_stats(character))
      |> assign(
        :input_disabled,
        not assigns.connected or assigns.thinking or assigns.scene_loading or
          session_dead?(assigns.session)
      )

    ~H"""
    <Layouts.play flash={@flash}>
      <.play_header
        session_id={@session.id}
        session_name={@session.name}
        world_clock={@world_clock}
        location_name={@location_name}
        quick_stats={@quick_stats}
      />

      <%!-- Below lg the page scrolls: the story panel fills the screen under the
           header (calc on dvh, so the phone toolbars do not cover the input),
           and Visuals and the character state come after it. From lg the
           panels sit side by side and the page does not scroll. --%>
      <div class="flex flex-none flex-col gap-3 px-2 py-2 sm:px-4 sm:py-3 lg:min-h-0 lg:flex-1 lg:flex-row lg:overflow-hidden">
        <div
          id="story-column"
          class="flex h-[calc(100dvh-5.5rem)] min-w-0 flex-none flex-col lg:h-auto lg:min-h-0 lg:flex-1"
        >
          <.narrative_panel
            streams={@streams}
            scene_loading={@scene_loading}
            thinking={@thinking}
            gm_reveal={@gm_reveal}
            clarification={@clarification}
            input_disabled={@input_disabled}
            session_status={@session.status}
          />
        </div>
        <.visual_panel
          location_name={@location_name}
          scene_image_url={@scene_image_url}
          present_npcs={@present_npcs}
          last_exchange={@last_exchange}
        />
      </div>

      <div class="shrink-0 px-2 pb-3 sm:px-4">
        <.state_panel character={@character} />
      </div>
    </Layouts.play>
    """
  end

  defp session_dead?(%{status: "dead"}), do: true

  defp session_dead?(session) do
    get_in(session.world_state || %{}, ["character", "vitality"]) == "dead"
  end

  defp maybe_start_scene_after_travel(socket, %{needs_scene: true}, session) do
    {:ok, _} = GameSessions.ensure_scene(session.id)
    assign(socket, :scene_loading, true)
  end

  defp maybe_start_scene_after_travel(socket, _payload, _session), do: socket

  defp spend_cap_message(:session),
    do:
      "The Game Master lays down the dice: this session has used its AI budget, so the story pauses here. Your progress is saved."

  defp spend_cap_message(:day),
    do:
      "The Game Master is resting until tomorrow: today's AI budget is used up. Your progress is saved; come back after midnight (Swedish time)."

  defp submit_action(socket, message, opts) do
    session_id = socket.assigns.session.id
    socket = assign(socket, :thinking, true)

    opts = Keyword.put(opts, :founder, socket.assigns[:admin_email])

    case GameSessions.submit_message(session_id, message, opts) do
      {:ok, %{status: :processing}} ->
        {:noreply, show_pending_action(socket, pending_action_text(socket, message, opts))}

      {:ok, %{status: :clarification}} ->
        {:noreply, assign(socket, :thinking, false)}

      {:error, reason} ->
        {:noreply, submit_failed(socket, reason)}
    end
  end

  defp submit_failed(socket, reason) do
    socket
    |> assign(:thinking, false)
    |> drop_pending_action()
    |> forget_expired_question(reason)
    |> put_flash(flash_kind(reason), submit_error(reason))
  end

  # An empty submit is a hint, so it is an info toast, which closes itself
  # (Layouts.flash_group); the other failures are errors that stay.
  defp flash_kind(:empty_message), do: :info
  defp flash_kind(_reason), do: :error

  defp forget_expired_question(socket, :clarification_expired),
    do: assign(socket, :clarification, nil)

  defp forget_expired_question(socket, _reason), do: socket

  defp submit_error(:empty_message), do: "Say something first."
  defp submit_error(:clarification_expired), do: "That question has passed. Say what you do."
  defp submit_error(:needs_scene), do: "Wait for the GM to describe the scene before you act."
  defp submit_error(:dead), do: "You are dead."
  defp submit_error(_reason), do: "Could not process that action."

  # The player's action shows in the story as soon as the server takes it, so
  # it sits above the GM text that streams next. The entry has a fixed id;
  # the turn's own entries replace it when the turn completes, and it goes
  # away when the turn fails.
  @pending_action_id "pending-player"

  defp show_pending_action(socket, ""), do: socket

  defp show_pending_action(socket, text) do
    stream_insert(socket, :entries, %{id: @pending_action_id, role: "player", text: text})
  end

  # An option pick sends no text: it plays the words of the pending question.
  defp pending_action_text(socket, message, opts) do
    picked = Keyword.get(opts, :clarification_id)

    case {String.trim(message), picked, socket.assigns.clarification} do
      {"", id, %{"clarification_id" => id} = pending} when not is_nil(id) ->
        String.trim(pending["player_text"] || pending["raw_action"] || "")

      {text, _id, _pending} ->
        text
    end
  end

  defp drop_pending_action(socket),
    do: stream_delete_by_dom_id(socket, :entries, "entries-" <> @pending_action_id)

  defp current_scene_image(session) do
    location_id = Map.get(session.world_state || %{}, "location_id")

    session.scenes
    |> Enum.find(&(&1.location_id == location_id))
    |> case do
      %{image_url: url} when is_binary(url) and url != "" -> url
      _ -> nil
    end
  end

  defp refresh_scenes(%{id: id} = session) do
    scenes =
      id
      |> GameSessions.get_session!()
      |> Repo.preload(:scenes)
      |> Map.get(:scenes)

    Map.put(session, :scenes, scenes)
  end

  defp append_entries(socket, entries) do
    Enum.reduce(entries, socket, fn entry, sock ->
      stream_insert(sock, :entries, entry)
    end)
  end
end
