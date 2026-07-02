defmodule TalesForgeWeb.PlayLive do
  use TalesForgeWeb, :live_view

  alias TalesForge.GameSessions
  alias TalesForge.PubSub.GameSession, as: SessionPubSub
  alias TalesForge.Repo

  @impl true
  def mount(%{"id" => id}, _session, socket) do
    if connected?(socket) do
      SessionPubSub.subscribe(id)
    end

    session =
      id
      |> GameSessions.get_session!()
      |> Repo.preload(:turns)

    :ok = GameSessions.ensure_agent_started(session)

    entries = load_entries(session)

    {:ok,
     socket
     |> assign(:page_title, session.name)
     |> assign(:session, session)
     |> assign(:thinking, false)
     |> assign(:clarification, nil)
     |> assign(:llm_source, "mock")
     |> stream(:entries, entries, reset: true)}
  end

  @impl true
  def handle_event("send_message", %{"message" => message}, socket) do
    submit_action(socket, message, [])
  end

  def handle_event("pick_clarification", %{"option_id" => option_id}, socket) do
    clarification = socket.assigns.clarification

    if clarification do
      submit_action(socket, "",
        clarification_id: clarification["clarification_id"],
        option_id: option_id
      )
    else
      {:noreply, socket}
    end
  end

  @impl true
  def handle_info({:turn_processing, _}, socket) do
    {:noreply, assign(socket, :thinking, true)}
  end

  def handle_info({:clarification_needed, clarification}, socket) do
    {:noreply,
     socket
     |> assign(:thinking, false)
     |> assign(:clarification, clarification)}
  end

  def handle_info({:turn_completed, payload}, socket) do
    session = Map.put(socket.assigns.session, :world_state, payload.world_state)

    {:noreply,
     socket
     |> assign(:thinking, false)
     |> assign(:clarification, nil)
     |> assign(:session, session)
     |> assign(:llm_source, payload.llm_source)
     |> append_entries(payload.entries)}
  end

  def handle_info({:turn_failed, reason}, socket) do
    {:noreply,
     socket
     |> assign(:thinking, false)
     |> put_flash(:error, "Turn failed: #{reason}")}
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

    ~H"""
    <Layouts.app flash={@flash}>
      <div class="mx-auto grid max-w-7xl gap-4 lg:grid-cols-[minmax(0,2fr)_minmax(0,1fr)]">
        <div class="space-y-4">
          <header class="rounded-xl border border-zinc-200 bg-white px-4 py-3">
            <.link navigate={~p"/"} class="text-sm text-amber-700 hover:underline">← Sessions</.link>
            <h1 class="mt-1 text-xl font-bold text-zinc-900">{@session.name}</h1>
            <p class="text-sm text-zinc-500">
              {@location_name} · {@world_clock} · GM source: {@llm_source}
            </p>
          </header>

          <section
            id="narrative-log"
            class="min-h-[28rem] space-y-4 overflow-y-auto rounded-xl border border-zinc-200 bg-zinc-50 p-4"
            phx-update="stream"
          >
            <div :for={{dom_id, entry} <- @streams.entries} id={dom_id} class="space-y-1">
              <p class={[
                "text-xs font-semibold uppercase tracking-wide",
                entry.role == "gm" && "text-amber-800",
                entry.role == "player" && "text-zinc-500"
              ]}>
                {if entry.role == "gm", do: "Game Master", else: "You"}
              </p>
              <div class={[
                "whitespace-pre-wrap rounded-lg px-3 py-2 text-sm leading-relaxed",
                entry.role == "gm" && "bg-white text-zinc-800 shadow-sm",
                entry.role == "player" && "bg-amber-100 text-zinc-900"
              ]}>
                {entry.text}
              </div>
              <p :if={entry.role == "gm" && entry[:mechanical]} class="text-xs text-zinc-500">
                {format_mechanical(entry.mechanical)}
              </p>
            </div>

            <p :if={@thinking} class="text-sm italic text-zinc-500">The GM is thinking…</p>
          </section>

          <section :if={@clarification} class="rounded-xl border border-amber-200 bg-amber-50 p-4">
            <p class="mb-3 text-sm font-medium text-amber-900">{@clarification["question"]}</p>
            <div class="space-y-2">
              <button
                :for={opt <- @clarification["options"]}
                type="button"
                phx-click="pick_clarification"
                phx-value-option_id={opt["id"]}
                class="block w-full rounded-lg border border-amber-300 bg-white px-3 py-2 text-left text-sm hover:bg-amber-100"
              >
                <span class="font-medium">{opt["label"]}</span>
                <span :if={opt["description"]} class="block text-zinc-600">{opt["description"]}</span>
              </button>
            </div>
          </section>

          <.form for={%{}} phx-submit="send_message" class="flex gap-2">
            <input
              type="text"
              name="message"
              placeholder="What do you do?"
              autocomplete="off"
              class="flex-1 rounded-lg border border-zinc-300 px-3 py-2"
              disabled={@thinking}
            />
            <button
              type="submit"
              class="rounded-lg bg-amber-700 px-4 py-2 font-medium text-white hover:bg-amber-800 disabled:opacity-50"
              disabled={@thinking}
            >
              Act
            </button>
          </.form>
        </div>

        <aside class="space-y-4">
          <section class="rounded-xl border border-zinc-200 bg-white p-4">
            <h2 class="mb-3 text-sm font-semibold uppercase tracking-wide text-zinc-500">Scene</h2>
            <div class="flex aspect-video items-center justify-center rounded-lg bg-zinc-100 text-sm text-zinc-500">
              Scene image (Phase 2)
            </div>
          </section>

          <section class="rounded-xl border border-zinc-200 bg-white p-4">
            <h2 class="mb-3 text-sm font-semibold uppercase tracking-wide text-zinc-500">
              Character
            </h2>
            <dl class="space-y-2 text-sm">
              <div class="flex justify-between">
                <dt class="text-zinc-500">Name</dt>
                <dd class="font-medium">{Map.get(@character, "name", "—")}</dd>
              </div>
              <div class="flex justify-between">
                <dt class="text-zinc-500">Wounds</dt>
                <dd class="font-medium">
                  {Map.get(@character, "wounds", 0)}/{Map.get(@character, "wound_max", 3)}
                </dd>
              </div>
              <div class="flex justify-between">
                <dt class="text-zinc-500">Coins</dt>
                <dd class="font-medium">{format_coins(Map.get(@character, "coins", %{}))}</dd>
              </div>
            </dl>
          </section>

          <section class="rounded-xl border border-zinc-200 bg-white p-4">
            <h2 class="mb-2 text-sm font-semibold uppercase tracking-wide text-zinc-500">Present</h2>
            <p class="text-sm text-zinc-600">Marta Kellen (barkeep)</p>
          </section>
        </aside>
      </div>
    </Layouts.app>
    """
  end

  defp submit_action(socket, message, opts) do
    session_id = socket.assigns.session.id
    socket = assign(socket, :thinking, true)

    case GameSessions.submit_message(session_id, message, opts) do
      {:ok, %{status: :processing}} ->
        {:noreply, socket}

      {:ok, %{status: :clarification}} ->
        {:noreply, assign(socket, :thinking, false)}

      {:error, :empty_message} ->
        {:noreply,
         socket |> assign(:thinking, false) |> put_flash(:error, "Say something first.")}

      {:error, _reason} ->
        {:noreply,
         socket
         |> assign(:thinking, false)
         |> put_flash(:error, "Could not process that action.")}
    end
  end

  defp load_entries(session) do
    session.turns
    |> Enum.sort_by(& &1.turn_number)
    |> Enum.flat_map(fn turn ->
      mechanical = turn.mechanical_resolution || %{}

      [
        %{id: "#{turn.id}-player", role: "player", text: turn.player_action},
        %{
          id: "#{turn.id}-gm",
          role: "gm",
          text: turn.narrative || "",
          mechanical: mechanical
        }
      ]
    end)
  end

  defp append_entries(socket, entries) do
    Enum.reduce(entries, socket, fn entry, sock ->
      stream_insert(sock, :entries, entry)
    end)
  end

  defp format_mechanical(%{"outcome" => "none"}), do: nil

  defp format_mechanical(mechanical) when is_map(mechanical) do
    skill = Map.get(mechanical, "skill")
    outcome = Map.get(mechanical, "outcome")
    roll = Map.get(mechanical, "roll")
    lp = Map.get(mechanical, "lp_awarded")

    parts =
      [
        skill && "Skill: #{skill}",
        outcome && "Outcome: #{outcome}",
        roll && "Roll: #{roll}",
        lp && "+#{lp} LP"
      ]
      |> Enum.reject(&is_nil/1)

    if parts == [], do: nil, else: Enum.join(parts, " · ")
  end

  defp format_mechanical(_), do: nil

  defp format_coins(coins) when is_map(coins) do
    gold = Map.get(coins, "gold", 0)
    silver = Map.get(coins, "silver", 0)
    copper = Map.get(coins, "copper", 0)
    "#{gold}g #{silver}s #{copper}c"
  end

  defp format_coins(_), do: "—"
end
