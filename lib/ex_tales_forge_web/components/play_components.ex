defmodule TalesForgeWeb.PlayComponents do
  @moduledoc false
  use TalesForgeWeb, :html

  alias TalesForge.Game.Mechanics
  alias TalesForge.Game.PlayPanel
  alias TalesForgeWeb.PlayLive.GmReveal

  attr :session_id, :string, required: true
  attr :session_name, :string, required: true
  attr :world_clock, :string, required: true
  attr :location_name, :string, required: true
  attr :quick_stats, :string, required: true

  def play_header(assigns) do
    ~H"""
    <header class="play-header shrink-0 px-3 py-1.5 sm:px-6 sm:py-3">
      <div class="flex flex-wrap items-center justify-between gap-x-3 gap-y-0.5 sm:gap-3">
        <div class="flex min-w-0 items-center gap-3 sm:gap-4">
          <.link
            navigate={~p"/"}
            class="play-label shrink-0 text-[var(--paper-accent)] hover:underline"
          >
            Tales Forge
          </.link>
          <h1 class="truncate font-serif text-base font-semibold sm:text-lg text-[var(--paper-ink)]">
            {@session_name}
          </h1>
          <.link
            href={~p"/admin/play/sessions/#{@session_id}"}
            class="play-label shrink-0 text-[var(--paper-muted)] hover:text-[var(--paper-accent)] hover:underline"
          >
            Admin
          </.link>
          <%!-- -my-2.5: the 44px tap area overlaps the header padding, so the bar keeps its height --%>
          <TalesForgeWeb.AppComponents.env_badge
            id="play-env-badge"
            switch_path={~p"/"}
            compact
            class="-my-2.5 shrink-0"
          />
        </div>
        <dl class="flex flex-wrap items-center gap-x-4 gap-y-0 text-xs sm:gap-x-6 sm:gap-y-1 sm:text-sm">
          <div class="flex items-baseline gap-2">
            <dt class="play-label">Time</dt>
            <dd class="font-medium text-[var(--paper-ink)]">{@world_clock}</dd>
          </div>
          <div class="flex items-baseline gap-2">
            <dt class="play-label">Location</dt>
            <dd class="font-medium text-[var(--paper-ink)]">{@location_name}</dd>
          </div>
          <div class="flex items-baseline gap-2">
            <dt class="play-label">Status</dt>
            <dd class="font-medium text-[var(--paper-ink)]">{@quick_stats}</dd>
          </div>
        </dl>
      </div>
    </header>
    """
  end

  attr :streams, :map, required: true
  attr :scene_loading, :boolean, required: true
  attr :thinking, :boolean, required: true
  attr :gm_reveal, GmReveal, required: true
  attr :clarification, :map, default: nil
  attr :input_disabled, :boolean, required: true
  attr :session_status, :string, default: "active"

  @doc """
  The story column of the play page: the narrative log, the GM's streamed
  reply (`gm_streaming/1`), any clarification question, and the action form
  (text input plus the Act button, `act_button/1`). The input and Act are
  disabled while a turn runs, and also before the page connects, because a
  submit at that time is not sent. On phones the input shrinks to the space
  left beside Act, so the button stays on screen down to a 320px viewport.

  When the player scrolled up and new text arrives, the "New text below"
  button shows above the action form. StoryScroll (assets/js/story_scroll.js)
  shows the button, hides it at the end of the story, and scrolls to the end
  when the player selects it. The wrapper is a polite live region, so a
  screen reader reads the button text when it shows.
  """
  @spec narrative_panel(map()) :: Phoenix.LiveView.Rendered.t()
  def narrative_panel(assigns) do
    ~H"""
    <section class="play-panel flex min-h-0 flex-1 flex-col overflow-hidden rounded-lg">
      <div class="border-b border-[var(--paper-rule)] px-3 py-1 sm:px-4 sm:py-2">
        <h2 class="play-label">Story</h2>
      </div>

      <%!-- The GM placeholders sit after the stream container, not inside it: every
           child of a phx-update="stream" element must be a stream item with an id.
           `contents` lets the entries and placeholders share one gap-4 column. --%>
      <%!-- StoryScroll (assets/js/story_scroll.js) keeps the newest text in view. --%>
      <div class="relative flex min-h-0 flex-1 flex-col">
        <div
          id="story-scroll"
          phx-hook="StoryScroll"
          class="flex min-h-0 flex-1 flex-col gap-4 overflow-y-auto bg-[var(--paper-margin)] p-3 sm:p-4"
        >
          <div id="narrative-log" class="contents" phx-update="stream">
            <div :for={{dom_id, entry} <- @streams.entries} id={dom_id} class="space-y-1">
              <.thought_entry :if={entry.role == "thought"} id={dom_id} entry={entry} />
              <p :if={entry.role != "thought"} class={entry_heading_class(entry)}>
                {entry_heading(entry)}
              </p>
              <div :if={entry.role != "thought"} class={entry_body_class(entry)}>
                <span class="play-narrative-body whitespace-pre-wrap">{entry.text}</span>
              </div>
              <p
                :if={entry.role != "thought" and Map.get(entry, :roll)}
                class="play-roll-line font-mono text-xs text-[var(--paper-muted)]"
                data-roll-line
              >
                {Map.get(entry, :roll)}
              </p>
            </div>
          </div>

          <p :if={@scene_loading} class="text-sm italic text-[var(--paper-muted)]">
            The GM is setting the scene…
          </p>
          <.gm_streaming :if={@thinking} reveal={@gm_reveal} />
        </div>

        <div
          id="story-new-text-region"
          phx-update="ignore"
          aria-live="polite"
          class="pointer-events-none absolute inset-x-0 bottom-2 flex justify-center"
        >
          <button
            id="story-new-text"
            type="button"
            hidden
            aria-controls="story-scroll"
            class="pointer-events-auto rounded-full bg-[var(--paper-accent)] px-3 py-1 text-sm font-medium text-white shadow hover:opacity-90 focus-visible:outline-2 focus-visible:outline-offset-2"
          >
            New text below <span aria-hidden="true">↓</span>
          </button>
        </div>
      </div>

      <div class="shrink-0 space-y-2 border-t border-[var(--paper-rule)] p-2 sm:space-y-3 sm:p-4">
        <p :if={@session_status == "dead"} class="text-sm italic text-[var(--paper-muted)]">
          You are dead.
        </p>
        <section
          :if={@clarification}
          class="rounded-lg border border-[var(--paper-rule)] bg-[var(--paper-bg)] p-3"
        >
          <p class="mb-2 text-sm font-medium text-[var(--paper-ink)]">{@clarification["question"]}</p>
          <div class="space-y-2">
            <button
              :for={opt <- @clarification["options"]}
              type="button"
              phx-click="pick_clarification"
              phx-value-option_id={opt["id"]}
              disabled={@input_disabled}
              class="block w-full rounded border border-[var(--paper-rule)] bg-[var(--paper-panel)] px-3 py-2 text-left text-sm hover:bg-[var(--paper-margin)] disabled:opacity-50"
            >
              <span class="font-medium">{opt["label"]}</span>
              <span :if={opt["description"]} class="block text-[var(--paper-muted)]">
                {opt["description"]}
              </span>
            </button>
          </div>
        </section>

        <%!-- min-w-0 lets the input shrink below its intrinsic width (~255px) and
             shrink-0 keeps Act whole, so both fit a 320px phone. --%>
        <.form
          for={%{}}
          id="action-form"
          phx-submit="send_message"
          class="flex w-full min-w-0 items-stretch gap-2"
        >
          <input
            type="text"
            name="message"
            placeholder={input_placeholder(@scene_loading, @session_status)}
            autocomplete="off"
            aria-label="Your action"
            class="min-w-0 flex-1 rounded border border-[var(--paper-rule)] bg-[var(--paper-panel)] px-3 py-2 text-[var(--paper-ink)] placeholder:text-[var(--paper-muted)]"
            disabled={@input_disabled}
          />
          <.act_button thinking={@thinking} disabled={@input_disabled} />
        </.form>
      </div>
    </section>
    """
  end

  attr :reveal, GmReveal, required: true

  @doc """
  The GM's reply while it streams (docs/design-gm-streaming.md). It mounts
  when the turn starts and shows Slick's typing dots where the reply will
  begin. The `.GmReveal` hook owns its content (`phx-update="ignore"`): it gets
  each `gm_text` push (the whole text so far) and reveals it after at least
  `min_delay_ms`, at the speed it arrives, no faster than one character per
  `min_ms_per_char` unless the backlog needs about 250 ms to clear. The
  committed GM entry replaces it at `:turn_completed`, so any part not yet
  revealed shows then. The heading keeps its space while hidden, so nothing
  shifts when the text replaces the dots.
  """
  @spec gm_streaming(map()) :: Phoenix.LiveView.Rendered.t()
  def gm_streaming(assigns) do
    ~H"""
    <div
      id="gm-streaming"
      class="space-y-1"
      phx-hook=".GmReveal"
      phx-update="ignore"
      data-min-delay-ms={@reveal.min_delay_ms}
      data-min-ms-per-char={@reveal.min_ms_per_char}
    >
      <p class={[entry_heading_class(%{role: "gm"}), "invisible"]} data-gm-heading>
        {entry_heading(%{role: "gm"})}
      </p>
      <div class={entry_body_class(%{role: "gm"})}>
        <div class="gm-typing" aria-hidden="true" data-gm-dots>
          <span></span><span></span><span></span>
        </div>
        <span class="play-narrative-body whitespace-pre-wrap" data-gm-body></span>
      </div>
      <span class="sr-only" role="status">The story continues…</span>
    </div>
    <script :type={Phoenix.LiveView.ColocatedHook} name=".GmReveal">
      // Paces the streamed GM text (docs/design-gm-streaming.md section 2).
      const CATCH_UP_MS = 250
      const NO_DOTS_UNDER_MS = 300
      const DOTS_OUT_MS = 120

      export default {
        mounted() {
          const data = this.el.dataset
          this.minDelay = Math.max(0, parseInt(data.minDelayMs, 10) || 0)
          this.msPerChar = Math.max(1, parseInt(data.minMsPerChar, 10) || 1)
          this.heading = this.el.querySelector("[data-gm-heading]")
          this.dots = this.el.querySelector("[data-gm-dots]")
          this.body = this.el.querySelector("[data-gm-body]")
          this.node = this.body.appendChild(document.createTextNode(""))
          this.text = ""
          this.shown = 0
          this.carry = 0
          this.startAt = performance.now() + this.minDelay
          // A pause under 300 ms shows no dots at all.
          if (this.minDelay < NO_DOTS_UNDER_MS) {
            this.dots.hidden = true
            this.dotsTimer = setTimeout(() => { if (this.shown === 0) this.dots.hidden = false }, NO_DOTS_UNDER_MS)
          }
          this.handleEvent("gm_text", ({text}) => this.receive(text || ""))
        },
        destroyed() {
          cancelAnimationFrame(this.frame)
          clearTimeout(this.dotsTimer)
          clearTimeout(this.waitTimer)
        },
        receive(text) {
          // A retry (:reset, or text that does not extend what is shown) starts over.
          if (!text.startsWith(this.text.slice(0, this.shown))) this.restart()
          this.text = text
          this.schedule()
        },
        restart() {
          this.shown = 0
          this.carry = 0
          this.node.data = ""
          this.heading.classList.add("invisible")
          this.dots.classList.remove("gm-typing-out")
          this.dots.hidden = false
        },
        schedule() {
          if (this.frame || this.shown >= this.text.length) return
          const wait = this.startAt - performance.now()
          if (wait > 0) {
            clearTimeout(this.waitTimer)
            this.waitTimer = setTimeout(() => this.schedule(), wait)
            return
          }
          this.last = performance.now()
          this.frame = requestAnimationFrame((now) => this.tick(now))
        },
        tick(now) {
          this.frame = null
          const dt = Math.max(0, now - this.last)
          this.last = now
          const backlog = this.text.length - this.shown
          if (backlog <= 0) return
          if (this.shown === 0) this.begin()
          // At most one character per msPerChar, unless the backlog needs
          // more to clear in about CATCH_UP_MS.
          const step = Math.max(dt / this.msPerChar, (backlog * dt) / CATCH_UP_MS) + this.carry
          const n = Math.min(backlog, Math.floor(step))
          this.carry = n === backlog ? 0 : step - n
          if (n > 0) {
            this.node.appendData(this.text.slice(this.shown, this.shown + n))
            this.shown += n
          }
          if (this.shown < this.text.length) this.frame = requestAnimationFrame((t) => this.tick(t))
        },
        begin() {
          clearTimeout(this.dotsTimer)
          this.heading.classList.remove("invisible")
          this.dots.classList.add("gm-typing-out")
          setTimeout(() => { if (this.shown > 0) this.dots.hidden = true }, DOTS_OUT_MS)
          this.body.classList.add("gm-text-in")
        }
      }
    </script>
    """
  end

  attr :thinking, :boolean, required: true
  attr :disabled, :boolean, required: true

  @doc """
  The Act button. From the submit until the commit it is disabled and reads
  "GM is writing…" with the typing dots; `phx-disable-with` covers the moment
  before the server answers.
  """
  @spec act_button(map()) :: Phoenix.LiveView.Rendered.t()
  def act_button(assigns) do
    ~H"""
    <button
      type="submit"
      id="act-button"
      class="shrink-0 rounded bg-[var(--paper-accent)] px-4 py-2 font-medium text-white hover:opacity-90 disabled:cursor-wait disabled:opacity-50"
      disabled={@disabled}
      aria-busy={to_string(@thinking)}
      phx-disable-with="GM is writing…"
    >
      <span :if={!@thinking}>Act</span>
      <span :if={@thinking}>GM is writing…</span>
      <span :if={@thinking} class="gm-typing gm-typing-inline" aria-hidden="true">
        <span></span><span></span><span></span>
      </span>
    </button>
    """
  end

  attr :location_name, :string, required: true
  attr :scene_image_url, :string, default: nil
  attr :present_npcs, :list, required: true
  attr :last_exchange, :string, default: nil

  def visual_panel(assigns) do
    ~H"""
    <section class="play-panel flex min-h-0 flex-1 flex-col overflow-hidden rounded-lg lg:max-w-md">
      <div class="border-b border-[var(--paper-rule)] px-4 py-2">
        <h2 class="play-label">Visuals</h2>
      </div>

      <div class="min-h-0 flex-1 space-y-4 overflow-y-auto p-4">
        <div class="overflow-hidden rounded-lg border border-[var(--paper-rule)]">
          <img
            :if={@scene_image_url}
            src={@scene_image_url}
            alt={@location_name}
            class="aspect-video w-full object-cover"
          />
          <div
            :if={!@scene_image_url}
            class="flex aspect-video flex-col items-center justify-center bg-[var(--paper-margin)] px-4 text-center"
          >
            <span class="play-label">Scene</span>
            <span class="mt-1 font-serif text-base font-medium text-[var(--paper-ink)]">
              {@location_name}
            </span>
          </div>
        </div>

        <div>
          <h3 class="play-label mb-2">Present</h3>
          <ul :if={@present_npcs != []} class="grid grid-cols-2 gap-2">
            <li
              :for={npc <- @present_npcs}
              class="flex items-center gap-2 rounded-lg border border-[var(--paper-rule)] bg-[var(--paper-panel)] p-2"
            >
              <.npc_avatar npc={npc} />
              <div class="min-w-0">
                <p class="truncate text-sm font-medium text-[var(--paper-ink)]">{npc.name}</p>
                <p class="truncate text-xs text-[var(--paper-muted)]">
                  {npc_role_label(npc)}
                </p>
                <p
                  :if={npc.wounds_label}
                  class="truncate text-xs text-[var(--paper-accent)]"
                  data-npc-wounds={npc.id}
                >
                  {npc.wounds_label}
                </p>
              </div>
            </li>
          </ul>
          <p :if={@present_npcs == []} class="text-sm text-[var(--paper-muted)]">No one nearby.</p>
          <div :if={@last_exchange} id="last-combat-exchange" class="mt-3">
            <h3 class="play-label mb-1">Last exchange</h3>
            <p class="text-xs text-[var(--paper-muted)]">{@last_exchange}</p>
          </div>
        </div>
      </div>
    </section>
    """
  end

  # Slick's thought spec: about 160 characters is about 3 lines at 390 px.
  @thought_clamp_chars 160

  attr :id, :string, required: true
  attr :entry, :map, required: true

  @doc """
  The player character's thought (board card 845b6b15): its own quiet entry
  after the GM entry, with a thin accent rule, italic serif text, an
  optional "about" chip for a known NPC, and a 3-line clamp with "Show all"
  for long text. Never streamed, never under a "Game Master" heading.
  """
  def thought_entry(assigns) do
    assigns =
      assigns
      |> assign(:about, Map.get(assigns.entry, :about_name))
      |> assign(:long, String.length(assigns.entry.text || "") > @thought_clamp_chars)

    ~H"""
    <div
      id={"#{@id}-thought"}
      role="note"
      aria-label={if @about, do: "Thought about #{@about}", else: "Thought"}
      data-role="thought"
      class={[
        "play-thought ml-3 sm:ml-6 max-w-none sm:max-w-xl border-l-2 border-[var(--paper-thought-rule)] py-0.5 pl-3",
        @long && "clamp"
      ]}
    >
      <p class="play-label flex min-h-5 items-center gap-2">
        <span aria-hidden="true" class="text-[13px] leading-none">💭</span>
        <span>{entry_heading(@entry)}</span>
        <span
          :if={@about}
          data-role="thought-about"
          class="inline-flex items-center gap-[5px] text-[11.5px] font-normal normal-case tracking-normal text-[var(--paper-muted)]"
        >
          about
          <span class="flex h-5 w-5 shrink-0 items-center justify-center overflow-hidden rounded-full border border-[var(--paper-rule)] bg-[var(--paper-margin)] text-[8.5px] font-semibold uppercase">
            <img
              :if={@entry[:about_portrait]}
              src={@entry[:about_portrait]}
              alt=""
              class="h-full w-full object-cover"
            />
            <span :if={!@entry[:about_portrait]}>{npc_initials(@about)}</span>
          </span>
          {@about}
        </span>
      </p>
      <p
        id={"#{@id}-thought-text"}
        class={[
          "play-narrative-body mt-0.5 text-sm italic leading-relaxed text-[var(--paper-thought-ink)]",
          @long && "line-clamp-3"
        ]}
      >
        {@entry.text}
      </p>
      <button
        :if={@long}
        type="button"
        id={"#{@id}-thought-more"}
        aria-expanded="false"
        aria-controls={"#{@id}-thought-text"}
        class="flex min-h-11 w-full items-center px-1 text-left text-[13px] font-medium text-[var(--paper-accent)]"
        phx-click={
          JS.toggle_class("line-clamp-3", to: "##{@id}-thought-text")
          |> JS.toggle_attribute({"aria-expanded", "true", "false"})
          |> JS.toggle(to: "##{@id}-thought-more [data-label]", display: "inline")
        }
      >
        <span data-label>Show all</span>
        <span data-label style="display: none">Show less</span>
      </button>
    </div>
    """
  end

  attr :npc, :map, required: true

  defp npc_avatar(assigns) do
    ~H"""
    <div class="flex h-10 w-10 shrink-0 items-center justify-center overflow-hidden rounded-full border border-[var(--paper-rule)] bg-[var(--paper-margin)]">
      <img
        :if={@npc.portrait_url}
        src={@npc.portrait_url}
        alt={@npc.name}
        class="h-full w-full object-cover"
      />
      <span
        :if={!@npc.portrait_url}
        class="text-xs font-semibold uppercase text-[var(--paper-muted)]"
      >
        {npc_initials(@npc.name)}
      </span>
    </div>
    """
  end

  attr :character, :map, required: true

  def state_panel(assigns) do
    ~H"""
    <section class="play-panel shrink-0 rounded-lg px-4 py-3 sm:px-6">
      <h2 class="play-label mb-3">Character &amp; gear</h2>
      <div class="grid gap-4 sm:grid-cols-2">
        <div class="space-y-2">
          <p class="font-serif text-base font-semibold text-[var(--paper-ink)]">
            {Map.get(@character, "name", "—")}
          </p>
          <p class="text-sm capitalize text-[var(--paper-muted)]">
            {Map.get(@character, "race", "unknown")}
          </p>
          <div class="space-y-1">
            <div class="flex justify-between text-xs text-[var(--paper-muted)]">
              <span>Wounds</span>
              <span>
                {Map.get(@character, "wounds", 0)}/{Map.get(@character, "wound_max", 3)}
              </span>
            </div>
            <div class="h-2 overflow-hidden rounded-full bg-[var(--paper-margin)]">
              <div
                class="h-full rounded-full bg-[var(--paper-accent)]"
                style={"width: #{wound_percent(@character)}%"}
              />
            </div>
          </div>
          <p class="text-sm text-[var(--paper-ink)]">
            <span class="play-label">Coins</span>
            {format_coins(Map.get(@character, "coins", %{}))}
          </p>
          <div id="character-skills">
            <h3 class="play-label mb-1">Skills</h3>
            <ul :if={skill_rows(@character) != []} class="space-y-0.5 text-sm text-[var(--paper-ink)]">
              <li
                :for={row <- skill_rows(@character)}
                class="flex justify-between gap-2"
                data-skill={row.skill}
                title={"Trained level #{row.raw}; rolls use #{row.effective} (with the stat bonus)"}
              >
                <span>{row.label}</span>
                <span class="font-mono">{row.effective}%</span>
              </li>
            </ul>
            <p :if={skill_rows(@character) == []} class="text-sm text-[var(--paper-muted)]">
              No trained skills
            </p>
          </div>
        </div>

        <div>
          <h3 class="play-label mb-2">Inventory</h3>
          <ul class="space-y-1 text-sm text-[var(--paper-ink)]">
            <li :for={item <- Map.get(@character, "inventory", [])}>
              {Map.get(item, "name", "item")}
              <span :if={Map.get(item, "quantity", 1) > 1} class="text-[var(--paper-muted)]">
                ×{Map.get(item, "quantity")}
              </span>
            </li>
            <li :if={Map.get(@character, "inventory", []) == []} class="text-[var(--paper-muted)]">
              Empty pack
            </li>
          </ul>
        </div>
      </div>
    </section>
    """
  end

  @doc """
  The people of the Present panel: the present NPCs, then the other
  characters of the session's cast at the current location, such as a minor
  foe (#270). Each person has a `wounds_label` when the person has a wound
  or is down (QA 2026-10-14 08:57). A dead person is never present (QA
  2026-10-15 retest, session 9a1ff8c2: a dead Marta, kept as a minor foe,
  stayed in the panel with an empty `present_npcs`).

      iex> cast = %{"marta_kellen" => %TalesForge.GameCharacter{slug: "marta_kellen",
      ...>   name: "Marta Kellen", minor: true, location_id: "inn", vitality: "dead"}}
      iex> TalesForgeWeb.PlayComponents.present_npcs(%{"location_id" => "inn", "present_npcs" => []}, cast)
      []
      iex> cast = put_in(cast["marta_kellen"].vitality, "down")
      iex> [marta] = TalesForgeWeb.PlayComponents.present_npcs(%{"location_id" => "inn"}, cast)
      iex> {marta.name, marta.wounds_label}
      {"Marta Kellen", "down · 0/3 wounds"}
  """
  defdelegate present_npcs(world_state, cast), to: PlayPanel

  @doc """
  The last combat exchange text of the world (`combat_last`), or nil. The
  text shows only at the place of the fight (QA 2026-10-15: the panel still
  showed the fight with Marta after the move to the square).

      iex> world = %{"location_id" => "square", "combat_last" => %{"text" => "Attack", "location_id" => "inn"}}
      iex> TalesForgeWeb.PlayComponents.last_exchange(world)
      nil
      iex> TalesForgeWeb.PlayComponents.last_exchange(%{world | "location_id" => "inn"})
      "Attack"
  """
  def last_exchange(world_state) when is_map(world_state) do
    case Map.get(world_state, "combat_last") do
      %{"text" => text, "location_id" => at} when is_binary(text) and is_binary(at) ->
        if at == world_state["location_id"], do: text

      %{"text" => text} when is_binary(text) ->
        text

      _ ->
        nil
    end
  end

  def last_exchange(_world_state), do: nil

  @doc "See `TalesForge.Game.PlayPanel.quick_stats/1`."
  defdelegate quick_stats(character), to: PlayPanel

  def entry_heading(%{role: "scene", location_name: name}), do: "You arrive at #{name}"
  def entry_heading(%{role: "gm"}), do: "Game Master"
  def entry_heading(%{role: "thought"}), do: "Thought"
  def entry_heading(%{role: "player"}), do: "You"
  def entry_heading(%{role: "npc", npc_name: name}) when is_binary(name), do: name
  def entry_heading(_), do: "Narrator"

  defp entry_heading_class(%{role: "scene"}),
    do: "play-label text-[var(--paper-accent)]"

  defp entry_heading_class(%{role: "gm"}),
    do: "play-label text-[var(--paper-ink)]"

  defp entry_heading_class(%{role: "player"}),
    do: "play-label text-[var(--paper-muted)]"

  defp entry_heading_class(%{role: "npc"}),
    do: "play-label font-medium text-[var(--paper-accent)]"

  defp entry_heading_class(_), do: "play-label"

  defp entry_body_class(%{role: "scene"}),
    do:
      "rounded border border-[var(--paper-rule)] bg-[var(--paper-panel)] px-3 py-2 text-sm text-[var(--paper-ink)] shadow-sm"

  defp entry_body_class(%{role: "gm"}),
    do: "rounded bg-[var(--paper-panel)] px-3 py-2 text-sm text-[var(--paper-ink)] shadow-sm"

  defp entry_body_class(%{role: "player"}),
    do:
      "rounded border border-[var(--paper-rule)] bg-[var(--paper-bg)] px-3 py-2 text-sm text-[var(--paper-ink)]"

  defp entry_body_class(%{role: "npc"}),
    do:
      "rounded border border-[var(--paper-accent)]/30 bg-[var(--paper-panel)] px-3 py-2 text-sm italic text-[var(--paper-ink)] shadow-sm"

  defp entry_body_class(_),
    do: "rounded bg-[var(--paper-panel)] px-3 py-2 text-sm text-[var(--paper-ink)]"

  defp input_placeholder(_scene_loading, "dead"), do: "You are dead."
  defp input_placeholder(true, _status), do: "Wait for the scene…"
  defp input_placeholder(_, _status), do: "What do you do?"

  def format_mechanical(_), do: nil

  @doc """
  The trained skills of `character` for the character panel, by name: the
  trained level (`raw`) and the level that rolls use (`effective`, with the
  stat bonus; `TalesForge.Game.Mechanics.effective_level/2`).

      iex> TalesForgeWeb.PlayComponents.skill_rows(%{"stats" => %{"DEX" => 10}, "skills" => %{"stealth" => 25, "melee_combat" => 0}})
      [%{skill: "stealth", label: "Stealth", raw: 25, effective: 25}]
  """
  def skill_rows(character) when is_map(character) do
    character
    |> Map.get("skills", %{})
    |> case do
      skills when is_map(skills) -> skills
      _ -> %{}
    end
    |> Enum.filter(fn {_skill, level} -> is_integer(level) and level > 0 end)
    |> Enum.sort_by(fn {skill, _level} -> skill end)
    |> Enum.map(&skill_row(character, &1))
  end

  def skill_rows(_character), do: []

  defp skill_row(character, {skill, level}) do
    %{
      skill: skill,
      label: skill |> String.replace("_", " ") |> String.capitalize(),
      raw: level,
      effective: Mechanics.effective_level(character, skill)
    }
  end

  @doc """
  The coins as gold, silver and copper, converted up first (QA 2026-10-14
  21:15: a commoner start showed "0g 20s 300c"). 10 copper is 1 silver and
  500 copper is 1 gold (`TalesForge.Game.Inventory`).

      iex> TalesForgeWeb.PlayComponents.format_coins(%{"gold" => 0, "silver" => 20, "copper" => 300})
      "1g 0s 0c"
      iex> TalesForgeWeb.PlayComponents.format_coins(%{"gold" => 2, "silver" => 7})
      "2g 7s 0c"
  """
  defdelegate format_coins(coins), to: PlayPanel

  defp wound_percent(character) do
    wounds = Map.get(character, "wounds", 0)
    wound_max = max(Map.get(character, "wound_max", 3), 1)
    wounds |> Kernel.*(100) |> div(wound_max) |> min(100)
  end

  defp npc_initials(name) when is_binary(name) do
    name
    |> String.split()
    |> Enum.take(2)
    |> Enum.map_join("", &String.first/1)
    |> String.upcase()
  end

  defp npc_initials(_), do: "?"

  defp npc_role_label(%{concern_priority: priority, role: role})
       when is_integer(priority) and priority >= 8 do
    "#{role} · troubled"
  end

  defp npc_role_label(%{role: role}), do: role
end
