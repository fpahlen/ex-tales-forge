defmodule TalesForgeWeb.CreateCharacterLive do
  @moduledoc """
  Player character creation screen (`/new/:adventure`).

  Four steps on one LiveView: the creation model, race, class and past
  occupation; the stats (the 75-point buy, or a 4d6 dice roll with
  one re-roll) with the race bonus choices; the skill budget (free levels from the
  class package, race and occupation, a suggested spread build, up to two
  signature skills); then a typed name and "Begin adventure", which starts a
  session with the created character in place of Elara. The description model
  replaces the middle steps with one step: the player writes a description,
  answers at most 2 questions, and approves the AI draft
  (`TalesForge.CharacterCreation.FromText`). Then the name step starts the game. All rules live in
  `TalesForge.CharacterCreation`; this module only keeps the draft and renders
  it. Creation makes no AI calls, so it costs nothing (the first character is
  free); the description model makes one or two AI calls. A point-buy draft lives in the LiveView process and a reload starts
  again. From the first dice roll or AI draft, the server keeps the draft
  (`TalesForge.CharacterDrafts`), so a reload keeps the draft and the roll.
  """

  use TalesForgeWeb, :live_view

  alias TalesForge.CharacterCreation, as: CC
  alias TalesForge.CharacterCreation.FromText
  alias TalesForge.CharacterDrafts
  alias TalesForge.GameSessions

  @adventures %{"tin_valley" => "Tin Valley", "crossroads_ledger" => "Crossroads Hamlet"}
  @steps [{"origin", "Race & class"}, {"stats", "Stats"}, {"skills", "Skills"}, {"name", "Name"}]
  @models [
    {"point_buy", "Point buy", "Spend 75 points on your stats, 3 to 18 for each stat."},
    {"stat_roll", "Roll the dice",
     "Roll 4d6 for each stat and keep the highest 3. You get one re-roll."},
    {"from_text", "Describe your character",
     "Write who you are. The AI makes a draft, and you approve it before play."}
  ]
  @later ["Background", "Standing", "Origin", "Personality & concerns", "AI assist"]
  @stats [
    {"STR", "Strength"},
    {"DEX", "Dexterity"},
    {"CON", "Constitution"},
    {"INT", "Intelligence"},
    {"WIS", "Wisdom"},
    {"CHA", "Charisma"}
  ]

  @doc "Adventures a character can be created for, id to display name."
  @spec adventures() :: %{String.t() => String.t()}
  def adventures, do: @adventures

  @impl true
  def mount(%{"adventure" => adventure}, _session, socket) do
    case Map.fetch(@adventures, adventure) do
      {:ok, adventure_name} ->
        owner = socket.assigns[:admin_github_login] || socket.assigns[:admin_email]
        draft = (owner && CharacterDrafts.get(owner, adventure)) || CC.new(adventure)

        {:ok,
         socket
         |> assign(:page_title, "Create a character · #{adventure_name}")
         |> assign(:adventure, adventure)
         |> assign(:adventure_name, adventure_name)
         |> assign(:options, CC.options(adventure))
         |> assign(:owner, owner)
         |> assign(:draft, draft)
         |> assign(:step, start_step(draft))
         |> assign(:description, "")
         |> assign(:questions, [])
         |> assign(:reading, false)
         |> assign(:text_error, nil)
         |> assign(:name_error, nil)
         |> assign(:refused, nil)}

      :error ->
        {:ok, socket |> put_flash(:error, "Unknown adventure.") |> push_navigate(to: ~p"/")}
    end
  end

  @impl true
  def handle_event("model", %{"id" => "from_text"}, socket) do
    {:noreply, socket} = update_draft(socket, CC.choose_model(socket.assigns.draft, "from_text"))
    {:noreply, assign(socket, :step, "describe")}
  end

  def handle_event("model", %{"id" => model}, socket),
    do: update_draft(socket, CC.choose_model(socket.assigns.draft, model))

  def handle_event("describe", %{"description" => text}, socket),
    do: {:noreply, read_text(assign(socket, description: text, questions: []), text, [])}

  def handle_event("answer", params, socket) do
    answers =
      socket.assigns.questions
      |> Enum.with_index()
      |> Enum.map(fn {q, i} -> {q, String.trim(params["answer_#{i}"] || "")} end)

    {:noreply, read_text(socket, socket.assigns.description, answers)}
  end

  def handle_event("rewrite", _params, socket) do
    draft = %{socket.assigns.draft | text_labels: nil, approved: false}
    {:noreply, assign(socket, draft: draft, questions: [], text_error: nil)}
  end

  def handle_event("approve", _params, socket) do
    {:noreply, socket} = update_draft(socket, CC.approve(socket.assigns.draft))
    {:noreply, assign(socket, :step, "name")}
  end

  def handle_event("reroll", _params, socket),
    do: update_draft(socket, CC.reroll_stats(socket.assigns.draft))

  def handle_event("race", %{"id" => race}, socket),
    do: update_draft(socket, CC.choose_race(socket.assigns.draft, race))

  def handle_event("class", %{"id" => class}, socket),
    do: update_draft(socket, CC.choose_class(socket.assigns.draft, class))

  def handle_event("occupation", %{"id" => occupation}, socket),
    do: update_draft(socket, CC.choose_occupation(socket.assigns.draft, occupation))

  def handle_event("skill", %{"skill" => skill, "delta" => delta}, socket) do
    draft = socket.assigns.draft
    level = Map.get(CC.skill_levels(draft), skill, 0) + String.to_integer(delta)
    update_draft(socket, CC.set_skill(draft, skill, level))
  end

  def handle_event("suggest_skills", _params, socket),
    do: update_draft(socket, {:ok, CC.suggest_skills(socket.assigns.draft)})

  def handle_event("stat", %{"stat" => stat, "delta" => delta}, socket) do
    draft = socket.assigns.draft
    value = Map.get(draft.base_stats, stat, 0) + String.to_integer(delta)
    update_draft(socket, CC.set_stat(draft, stat, value))
  end

  def handle_event("pick", %{"stat" => stat}, socket) do
    draft = socket.assigns.draft
    count = race_choice(socket.assigns.options, draft.race)["count"]
    update_draft(socket, CC.pick_race_bonus(draft, next_picks(draft.race_picks, stat, count)))
  end

  def handle_event("name", %{"name" => name}, socket) do
    case CC.set_name(socket.assigns.draft, name) do
      {:ok, draft} -> {:noreply, socket |> save(draft) |> assign(draft: draft, name_error: nil)}
      {:error, {:name, message}} -> {:noreply, assign(socket, :name_error, sentence(message))}
    end
  end

  def handle_event("go", %{"step" => step}, socket) do
    if step_open?(step, socket.assigns.draft),
      do: {:noreply, assign(socket, step: step, refused: nil)},
      else: {:noreply, socket}
  end

  def handle_event("begin", %{"name" => name}, socket) do
    with {:ok, draft} <- name_result(CC.set_name(socket.assigns.draft, name)),
         {:ok, character} <- CC.finalize(draft) do
      start(socket, draft, character)
    else
      {:error, errors} -> {:noreply, show_finalize_errors(socket, errors)}
    end
  end

  # One AI call in a task. The answers give a second call with no questions.
  defp read_text(socket, text, answers) do
    adventure = socket.assigns.adventure

    socket
    |> assign(reading: true, text_error: nil)
    |> start_async(:read_text, fn -> {FromText.read(adventure, text, answers), answers} end)
  end

  @impl true
  def handle_async(:read_text, {:ok, {{:ok, %{questions: [_ | _] = qs}}, []}}, socket),
    do: {:noreply, assign(socket, reading: false, questions: qs)}

  def handle_async(:read_text, {:ok, {{:ok, reading}, _answers}}, socket) do
    {:ok, draft} = FromText.build(socket.assigns.draft, reading)
    {:noreply, socket} = update_draft(socket, {:ok, draft})
    {:noreply, assign(socket, reading: false, questions: [])}
  end

  def handle_async(:read_text, {:ok, {{:error, :empty}, _}}, socket),
    do: {:noreply, assign(socket, reading: false, text_error: "Write a short description.")}

  def handle_async(:read_text, _result, socket) do
    {:noreply,
     assign(socket,
       reading: false,
       text_error: "The AI needs another try. Send the description again."
     )}
  end

  defp start_step(%{model: "from_text", text_labels: labels}) when is_map(labels), do: "describe"
  defp start_step(_draft), do: "origin"

  defp name_result({:ok, draft}), do: {:ok, draft}
  defp name_result({:error, error}), do: {:error, [error]}

  defp start(socket, draft, character) do
    attrs = %{
      adventure_id: socket.assigns.adventure,
      name: "#{socket.assigns.adventure_name} · #{draft.name}",
      character: character
    }

    case GameSessions.create_session(attrs) do
      {:ok, session} ->
        if socket.assigns.owner,
          do: CharacterDrafts.delete(socket.assigns.owner, socket.assigns.adventure)

        {:noreply, push_navigate(socket, to: ~p"/play/#{session.id}")}

      {:error, _reason} ->
        {:noreply, put_flash(socket, :error, "Could not start the adventure. Please try again.")}
    end
  end

  defp show_finalize_errors(socket, errors) do
    cond do
      message = Keyword.get(errors, :name) -> assign(socket, :name_error, sentence(message))
      Keyword.has_key?(errors, :approval) -> assign(socket, step: "describe", name_error: nil)
      Keyword.has_key?(errors, :skills) -> assign(socket, step: "skills", name_error: nil)
      true -> assign(socket, step: "stats", name_error: nil)
    end
  end

  defp update_draft(socket, {:ok, draft}),
    do: {:noreply, socket |> save(draft) |> assign(draft: draft, refused: nil)}

  defp update_draft(socket, {:error, {_field, message}}),
    do: {:noreply, assign(socket, :refused, sentence(message))}

  # The server keeps a draft from the first dice roll or AI draft. A point-buy
  # draft without either stays in the LiveView process, as before.
  defp save(%{assigns: %{owner: nil}} = socket, _draft), do: socket
  defp save(socket, %{rolled_stats: nil, text_labels: nil}), do: socket

  defp save(socket, draft) do
    :ok = CharacterDrafts.put(socket.assigns.owner, draft)
    socket
  end

  # A two-stat bonus always holds two picks: a new stat replaces the oldest one.
  defp next_picks(_picks, stat, 1), do: [stat]

  defp next_picks(picks, stat, count) do
    if stat in picks, do: picks, else: Enum.take(picks ++ [stat], -count)
  end

  defp step_open?("origin", _draft), do: true
  defp step_open?("describe", draft), do: draft.model == "from_text"
  defp step_open?("name", %{model: "from_text"} = draft), do: draft.approved
  defp step_open?("stats", _draft), do: true
  defp step_open?("skills", draft), do: stats_errors(draft) == []
  defp step_open?("name", draft), do: stats_errors(draft) == [] and skill_errors(draft) == []
  defp step_open?(_, _draft), do: false

  defp stats_errors(draft), do: errors_for(draft, [:stats, :race_picks])
  defp skill_errors(draft), do: errors_for(draft, [:skills])

  defp errors_for(draft, fields) do
    case CC.validate(draft) do
      :ok -> []
      {:error, errors} -> for {field, msg} <- errors, field in fields, do: sentence(msg)
    end
  end

  defp race_choice(options, race), do: Enum.find(options.races, &(&1.id == race)).choice

  # --- render -----------------------------------------------------------------------

  @impl true
  def render(assigns) do
    assigns =
      assigns
      |> assign(:steps, @steps)
      |> assign(:later, @later)
      |> assign(:stats_errors, stats_errors(assigns.draft))
      |> assign(:skill_errors, skill_errors(assigns.draft))
      |> assign(:points_left, CC.points_left(assigns.draft))

    ~H"""
    <Layouts.app flash={@flash}>
      <div id="create-character" class="paper-themed space-y-6">
        <header class="space-y-2">
          <p class="play-label text-[var(--paper-accent)]">New character · {@adventure_name}</p>
          <h1 class="font-serif text-3xl font-bold text-[var(--paper-ink)]">Create your character</h1>
          <p class="text-[var(--paper-muted)]">
            Choose who you are, spend your points and give yourself a name.
            <span class="ml-1 inline-block rounded bg-[var(--paper-ok-bg)] px-2 py-0.5 text-xs font-medium text-[var(--paper-ok-ink)]">
              Your first character is free
            </span>
          </p>
        </header>

        <nav :if={@draft.model != "from_text"} aria-label="Creation steps" class="space-y-2">
          <ol class="flex flex-wrap gap-2">
            <li :for={{{id, label}, i} <- Enum.with_index(@steps, 1)}>
              <button
                type="button"
                id={"step-#{id}"}
                phx-click="go"
                phx-value-step={id}
                disabled={
                  (id in ["skills", "name"] and @stats_errors != []) or
                    (id == "name" and @skill_errors != [])
                }
                aria-current={@step == id && "step"}
                class={[
                  "rounded-full border px-3 py-1 text-sm font-medium disabled:opacity-40",
                  if(@step == id,
                    do:
                      "border-[var(--paper-accent)] bg-[var(--paper-accent)] text-[var(--paper-on-accent)]",
                    else: "border-[var(--paper-rule)] bg-[var(--paper-panel)] text-[var(--paper-ink)]"
                  )
                ]}
              >
                {i}. {label}
              </button>
            </li>
          </ol>
          <p id="later-steps" class="text-xs text-[var(--paper-muted)]">
            Coming later: {Enum.join(@later, " · ")}
          </p>
        </nav>

        <p
          :if={@refused}
          id="refused"
          role="alert"
          class="rounded border border-[var(--paper-danger-rule)] px-3 py-2 text-sm text-[var(--paper-danger-ink)]"
        >
          {@refused}
        </p>

        <.origin_step :if={@step == "origin"} draft={@draft} options={@options} />
        <.describe_step
          :if={@step == "describe"}
          draft={@draft}
          description={@description}
          questions={@questions}
          reading={@reading}
          text_error={@text_error}
        />
        <.stats_step
          :if={@step == "stats"}
          draft={@draft}
          options={@options}
          points_left={@points_left}
          errors={@stats_errors}
        />
        <.skills_step
          :if={@step == "skills"}
          draft={@draft}
          options={@options}
          errors={@skill_errors}
        />
        <.name_step :if={@step == "name"} draft={@draft} options={@options} name_error={@name_error} />
      </div>
    </Layouts.app>
    """
  end

  attr :draft, :map, required: true
  attr :options, :map, required: true

  defp origin_step(assigns) do
    class = Enum.find(assigns.options.classes, &(&1.id == assigns.draft.class))

    assigns =
      assigns
      |> assign(:default_occupation, class && class.occupation)
      |> assign(:models, @models)

    ~H"""
    <section id="origin-step" class="space-y-6">
      <fieldset id="creation-model" class="space-y-2">
        <legend class="play-label mb-2">How you make your stats</legend>
        <div role="radiogroup" aria-label="Creation model" class="grid gap-2 sm:grid-cols-2">
          <.choice
            :for={{id, label, description} <- @models}
            event="model"
            id={id}
            label={label}
            description={description}
            selected={@draft.model == id}
          />
        </div>
      </fieldset>

      <p :if={@draft.model == "from_text"} class="text-sm text-[var(--paper-muted)]">
        The AI chooses race, class, occupation, stats and skills from your description.
      </p>

      <fieldset :if={@draft.model != "from_text"} class="space-y-2">
        <legend class="play-label mb-2">Race</legend>
        <div role="radiogroup" aria-label="Race" class="grid gap-2 sm:grid-cols-2">
          <.choice
            :for={race <- @options.races}
            event="race"
            id={race.id}
            label={label(race.id)}
            description={race.description}
            selected={@draft.race == race.id}
          />
        </div>
      </fieldset>

      <fieldset :if={@draft.model != "from_text"} class="space-y-2">
        <legend class="play-label mb-2">Class</legend>
        <div role="radiogroup" aria-label="Class" class="grid gap-2 sm:grid-cols-2">
          <.choice
            :for={class <- @options.classes}
            event="class"
            id={class.id}
            label={class_label(class.id)}
            description={class.description}
            selected={@draft.class == class.id}
          />
        </div>
      </fieldset>

      <fieldset :if={@draft.model != "from_text"} class="space-y-2">
        <legend class="play-label mb-2">Past occupation</legend>
        <p class="text-sm text-[var(--paper-muted)]">
          What you did before adventuring: free skill levels on top of your class.
          <span :if={@default_occupation}>
            Suggested for {class_label(@draft.class)}: {label(@default_occupation)}.
          </span>
        </p>
        <div role="radiogroup" aria-label="Past occupation" class="grid gap-2 sm:grid-cols-2">
          <.choice
            :for={occupation <- @options.occupations}
            event="occupation"
            id={occupation.id}
            label={label(occupation.id)}
            description={occupation.description <> " " <> skill_bonus_text(occupation.skills)}
            selected={@draft.occupation == occupation.id}
          />
        </div>
      </fieldset>

      <.step_nav next={if @draft.model == "from_text", do: "describe", else: "stats"} />
    </section>
    """
  end

  attr :event, :string, required: true
  attr :id, :string, required: true
  attr :label, :string, required: true
  attr :description, :string, required: true
  attr :selected, :boolean, required: true

  defp choice(assigns) do
    ~H"""
    <button
      type="button"
      role="radio"
      aria-checked={to_string(@selected)}
      id={"#{@event}-#{@id}"}
      phx-click={@event}
      phx-value-id={@id}
      class={[
        "play-panel rounded-lg px-4 py-3 text-left transition",
        @selected && "!border-2 !border-[var(--paper-accent)] !bg-[var(--paper-margin)]"
      ]}
    >
      <span class="flex items-center justify-between gap-2 font-serif font-semibold text-[var(--paper-ink)]">
        {@label}
        <span :if={@selected} class="text-sm text-[var(--paper-accent)]" aria-hidden="true">✓</span>
      </span>
      <span class="block text-sm text-[var(--paper-muted)]">{@description}</span>
    </button>
    """
  end

  attr :draft, :map, required: true
  attr :options, :map, required: true
  attr :points_left, :integer, required: true
  attr :errors, :list, required: true

  defp stats_step(assigns) do
    pb = assigns.options.point_buy

    assigns =
      assigns
      |> assign(:min, pb["min"])
      |> assign(:max, pb["max"])
      |> assign(:budget, pb["budget"])
      |> assign(:modifiers, CC.race_modifiers(assigns.draft))
      |> assign(:final, CC.final_stats(assigns.draft))
      |> assign(:choice, race_choice(assigns.options, assigns.draft.race))
      |> assign(:stat_names, @stats)
      |> assign(:rolled, assigns.draft.model == "stat_roll")

    ~H"""
    <section id="stats-step" class="space-y-4">
      <div
        :if={@rolled}
        id="stat-roll"
        class="play-panel flex items-center justify-between gap-3 rounded-lg px-4 py-3"
      >
        <div>
          <p class="play-label">Rolled stats</p>
          <p class="text-xs text-[var(--paper-muted)]">
            4d6 for each stat, the highest 3 count. A race bonus stops at {@max}.
          </p>
        </div>
        <button
          :if={@draft.rerolls_left > 0}
          type="button"
          id="reroll"
          phx-click="reroll"
          class="rounded border border-[var(--paper-rule)] px-3 py-1 text-sm font-medium text-[var(--paper-ink)] hover:opacity-80"
        >
          Re-roll all ({@draft.rerolls_left} left)
        </button>
        <p :if={@draft.rerolls_left == 0} id="reroll-used" class="text-sm text-[var(--paper-muted)]">
          You used your re-roll.
        </p>
      </div>
      <div
        :if={!@rolled}
        class="play-panel flex items-center justify-between gap-3 rounded-lg px-4 py-3"
      >
        <div>
          <p class="play-label">Points left</p>
          <p class="text-xs text-[var(--paper-muted)]">
            {@budget} to spend, {@min}–{@max} per stat
          </p>
        </div>
        <p
          id="points-left"
          class={[
            "font-serif text-3xl font-bold",
            if(@points_left < 0,
              do: "text-[var(--paper-danger-ink)]",
              else: "text-[var(--paper-ink)]"
            )
          ]}
        >
          {@points_left}
        </p>
      </div>

      <div :if={@choice} id="race-bonus" class="play-panel space-y-2 rounded-lg px-4 py-3">
        <p class="play-label">{label(@draft.race)} bonus</p>
        <p class="text-sm text-[var(--paper-muted)]">
          +{@choice["amount"]} to {if @choice["count"] == 1,
            do: Enum.join(@choice["from"], " or "),
            else: "any #{@choice["count"]} stats"}{if @choice["count"] > 1,
            do: ". Pick another to move a bonus.",
            else: "."}
        </p>
        <div class="flex flex-wrap gap-2">
          <button
            :for={stat <- @choice["from"]}
            type="button"
            id={"pick-#{stat}"}
            phx-click="pick"
            phx-value-stat={stat}
            aria-pressed={to_string(stat in @draft.race_picks)}
            class={[
              "rounded-full border px-3 py-1 text-sm font-medium",
              if(stat in @draft.race_picks,
                do:
                  "border-[var(--paper-accent)] bg-[var(--paper-accent)] text-[var(--paper-on-accent)]",
                else: "border-[var(--paper-rule)] text-[var(--paper-ink)]"
              )
            ]}
          >
            {stat}
          </button>
        </div>
      </div>

      <div class="play-panel rounded-lg">
        <div class="grid grid-cols-[1fr_auto_3rem_3rem] items-center gap-x-3 border-b border-[var(--paper-rule)] px-4 py-2">
          <span class="play-label">Stat</span>
          <span class="play-label text-center">{if @rolled, do: "Roll", else: "Points"}</span>
          <span class="play-label text-center">Race</span>
          <span class="play-label text-center">Total</span>
        </div>
        <div
          :for={{stat, name} <- @stat_names}
          id={"stat-#{stat}"}
          class="grid grid-cols-[1fr_auto_3rem_3rem] items-center gap-x-3 border-b border-[var(--paper-rule)] px-4 py-2 last:border-b-0"
        >
          <span class="min-w-0">
            <span class="font-semibold text-[var(--paper-ink)]">{stat}</span>
            <span class="ml-2 hidden text-sm text-[var(--paper-muted)] sm:inline">{name}</span>
          </span>
          <span class="flex items-center gap-2">
            <button
              :if={!@rolled}
              type="button"
              id={"dec-#{stat}"}
              phx-click="stat"
              phx-value-stat={stat}
              phx-value-delta="-1"
              disabled={@draft.base_stats[stat] <= @min}
              aria-label={"Lower #{name}"}
              class="size-9 rounded border border-[var(--paper-rule)] text-lg text-[var(--paper-ink)] disabled:opacity-30"
            >
              −
            </button>
            <span id={"base-#{stat}"} class="w-6 text-center font-mono text-[var(--paper-ink)]">
              {@draft.base_stats[stat]}
            </span>
            <button
              :if={!@rolled}
              type="button"
              id={"inc-#{stat}"}
              phx-click="stat"
              phx-value-stat={stat}
              phx-value-delta="1"
              disabled={@draft.base_stats[stat] >= @max or @points_left <= 0}
              aria-label={"Raise #{name}"}
              class="size-9 rounded border border-[var(--paper-rule)] text-lg text-[var(--paper-ink)] disabled:opacity-30"
            >
              +
            </button>
          </span>
          <span class="text-center text-sm text-[var(--paper-muted)]">
            {signed(Map.get(@modifiers, stat, 0))}
          </span>
          <span
            id={"total-#{stat}"}
            class={[
              "text-center font-serif text-lg font-semibold",
              if(@final[stat] < @min or @final[stat] > @max,
                do: "text-[var(--paper-danger-ink)]",
                else: "text-[var(--paper-ink)]"
              )
            ]}
          >
            {@final[stat]}
          </span>
        </div>
      </div>

      <ul :if={@errors != []} id="stats-errors" role="alert" class="space-y-1">
        <li :for={error <- @errors} class="text-sm text-[var(--paper-danger-ink)]">{error}</li>
      </ul>

      <.step_nav back="origin" next="skills" next_disabled={@errors != []} />
    </section>
    """
  end

  attr :draft, :map, required: true
  attr :options, :map, required: true
  attr :errors, :list, required: true

  defp skills_step(assigns) do
    rules = assigns.options.skills
    levels = CC.skill_levels(assigns.draft)

    assigns =
      assigns
      |> assign(:rules, rules)
      |> assign(:levels, levels)
      |> assign(:free, CC.free_skills(assigns.draft))
      |> assign(:left, CC.skill_points_left(assigns.draft))
      |> assign(:budget, CC.skill_budget(assigns.draft))
      |> assign(:signatures, Enum.count(levels, fn {_s, l} -> l > rules["cap"] end))
      |> assign(:skill_count, map_size(levels))

    ~H"""
    <section id="skills-step" class="space-y-4">
      <div class="play-panel flex items-center justify-between gap-3 rounded-lg px-4 py-3">
        <div class="min-w-0">
          <p class="play-label">Skill points left</p>
          <p class="text-xs text-[var(--paper-muted)]">
            {@budget} to spend. Levels 1–3 cost 1, 4–5 cost 2. Up to {@rules["signature_max"]} signature skills may go to {@rules[
              "signature_cap"
            ]} (3 per level).
          </p>
        </div>
        <p
          id="skill-points-left"
          class={[
            "font-serif text-3xl font-bold",
            if(@left < 0, do: "text-[var(--paper-danger-ink)]", else: "text-[var(--paper-ink)]")
          ]}
        >
          {@left}
        </p>
      </div>

      <div class="flex flex-wrap items-center justify-between gap-2">
        <p class="text-sm text-[var(--paper-muted)]">
          <span id="skill-count">{@skill_count}</span>
          skills (at least {@rules["min_skills"]}) · <span id="signature-count">{@signatures}</span>
          of {@rules["signature_max"]} signature
        </p>
        <button
          type="button"
          id="suggest-skills"
          phx-click="suggest_skills"
          class="rounded border border-[var(--paper-rule)] px-3 py-1 text-sm font-medium text-[var(--paper-ink)] hover:opacity-80"
        >
          Suggest a spread
        </button>
      </div>

      <div class="play-panel rounded-lg">
        <div class="grid grid-cols-[1fr_3rem_auto] items-center gap-x-3 border-b border-[var(--paper-rule)] px-4 py-2">
          <span class="play-label">Skill</span>
          <span class="play-label text-center">Free</span>
          <span class="play-label text-center">Level</span>
        </div>
        <div
          :for={%{id: skill, stat: stat} <- @options.skill_list}
          id={"skill-#{skill}"}
          class="grid grid-cols-[1fr_3rem_auto] items-center gap-x-3 border-b border-[var(--paper-rule)] px-4 py-2 last:border-b-0"
        >
          <span class="min-w-0">
            <span class="font-semibold text-[var(--paper-ink)]">{label(skill)}</span>
            <span class="ml-1 text-xs text-[var(--paper-muted)]">{stat}</span>
            <span
              :if={Map.get(@levels, skill, 0) > @rules["cap"]}
              class="ml-1 inline-block rounded bg-[var(--paper-margin)] px-1.5 py-0.5 text-xs font-medium text-[var(--paper-accent)]"
            >
              Signature
            </span>
          </span>
          <span class="text-center text-sm text-[var(--paper-muted)]">
            {free_text(Map.get(@free, skill, 0))}
          </span>
          <span class="flex items-center gap-2">
            <button
              type="button"
              id={"skill-dec-#{skill}"}
              phx-click="skill"
              phx-value-skill={skill}
              phx-value-delta="-1"
              disabled={Map.get(@levels, skill, 0) <= Map.get(@free, skill, 0)}
              aria-label={"Lower #{label(skill)}"}
              class="size-9 rounded border border-[var(--paper-rule)] text-lg text-[var(--paper-ink)] disabled:opacity-30"
            >
              −
            </button>
            <span
              id={"skill-level-#{skill}"}
              class="w-6 text-center font-serif text-lg font-semibold text-[var(--paper-ink)]"
            >
              {Map.get(@levels, skill, 0)}
            </span>
            <button
              type="button"
              id={"skill-inc-#{skill}"}
              phx-click="skill"
              phx-value-skill={skill}
              phx-value-delta="1"
              disabled={not can_raise?(Map.get(@levels, skill, 0), @left, @signatures, @rules)}
              aria-label={"Raise #{label(skill)}"}
              class="size-9 rounded border border-[var(--paper-rule)] text-lg text-[var(--paper-ink)] disabled:opacity-30"
            >
              +
            </button>
          </span>
        </div>
      </div>

      <ul :if={@errors != []} id="skills-errors" role="alert" class="space-y-1">
        <li :for={error <- @errors} class="text-sm text-[var(--paper-danger-ink)]">{error}</li>
      </ul>

      <.step_nav back="stats" next="name" next_disabled={@errors != []} />
    </section>
    """
  end

  # One more level is affordable, under the signature cap, and a new signature
  # skill only while there is room for one.
  defp can_raise?(level, left, signatures, rules) do
    costs = rules["level_costs"]
    price = Enum.at(costs, level, List.last(costs))

    level < rules["signature_cap"] and price <= left and
      (level != rules["cap"] or signatures < rules["signature_max"])
  end

  defp free_text(0), do: "—"
  defp free_text(level), do: to_string(level)

  defp skill_bonus_text(skills) do
    skills
    |> Enum.sort_by(fn {skill, level} -> {-level, skill} end)
    |> Enum.map_join(", ", fn {skill, level} -> "#{label(skill)} +#{level}" end)
  end

  attr :draft, :map, required: true
  attr :description, :string, required: true
  attr :questions, :list, required: true
  attr :reading, :boolean, required: true
  attr :text_error, :string, default: nil

  defp describe_step(assigns) do
    assigns =
      assigns
      |> assign(:labels, assigns.draft.text_labels)
      |> assign(:final, CC.final_stats(assigns.draft))
      |> assign(
        :skills,
        assigns.draft |> CC.skill_levels() |> Enum.sort_by(fn {s, l} -> {-l, s} end)
      )
      |> assign(:stat_names, @stats)

    ~H"""
    <section id="describe-step" class="space-y-4">
      <p :if={@reading} id="reading" class="text-sm text-[var(--paper-muted)]">
        The AI reads your description…
      </p>
      <p
        :if={@text_error}
        id="text-error"
        role="alert"
        class="text-sm text-[var(--paper-danger-ink)]"
      >
        {@text_error}
      </p>

      <.form
        :if={is_nil(@labels) and @questions == []}
        for={%{}}
        id="describe-form"
        phx-submit="describe"
        class="play-panel space-y-2 rounded-lg px-4 py-3"
      >
        <label for="description" class="play-label">Describe your character</label>
        <p class="text-sm text-[var(--paper-muted)]">
          Write who your character is: people, past work, strengths and a name.
          The AI asks at most {FromText.max_questions()} questions.
        </p>
        <textarea
          id="description"
          name="description"
          rows="5"
          maxlength="2000"
          class="w-full rounded border border-[var(--paper-rule)] bg-[var(--paper-bg)] px-3 py-2 text-[var(--paper-ink)]"
        >{@description}</textarea>
        <button
          type="submit"
          id="read-description"
          disabled={@reading}
          class="rounded bg-[var(--paper-accent)] px-4 py-2 font-medium text-[var(--paper-on-accent)] disabled:opacity-40"
        >
          Make a draft
        </button>
      </.form>

      <.form
        :if={is_nil(@labels) and @questions != []}
        for={%{}}
        id="questions-form"
        phx-submit="answer"
        class="play-panel space-y-3 rounded-lg px-4 py-3"
      >
        <p class="play-label">The AI has {length(@questions)} questions</p>
        <div :for={{q, i} <- Enum.with_index(@questions)} class="space-y-1">
          <label for={"answer_#{i}"} class="text-sm text-[var(--paper-ink)]">{q}</label>
          <input
            id={"answer_#{i}"}
            name={"answer_#{i}"}
            type="text"
            autocomplete="off"
            class="w-full rounded border border-[var(--paper-rule)] bg-[var(--paper-bg)] px-3 py-2 text-[var(--paper-ink)]"
          />
        </div>
        <button
          type="submit"
          id="send-answers"
          disabled={@reading}
          class="rounded bg-[var(--paper-accent)] px-4 py-2 font-medium text-[var(--paper-on-accent)] disabled:opacity-40"
        >
          Make a draft
        </button>
      </.form>

      <div :if={@labels} id="ai-draft" class="play-panel space-y-3 rounded-lg px-4 py-3">
        <p class="play-label">AI draft · approve it before play</p>
        <dl class="grid grid-cols-2 gap-2 text-sm sm:grid-cols-4">
          <div :for={field <- ~w(name race class occupation)} id={"label-#{field}"}>
            <dt class="play-label">{label(field)}</dt>
            <dd class="text-[var(--paper-ink)]">
              {draft_value(@draft, field)}
              <span class="block text-xs text-[var(--paper-muted)]">
                {confidence_text(@labels[field])}
              </span>
            </dd>
          </div>
        </dl>
        <dl class="grid grid-cols-3 gap-2 sm:grid-cols-6">
          <div
            :for={{stat, _name} <- @stat_names}
            class="rounded bg-[var(--paper-margin)] px-2 py-1 text-center"
          >
            <dt class="play-label">{stat}</dt>
            <dd
              id={"draft-stat-#{stat}"}
              class="font-serif text-lg font-semibold text-[var(--paper-ink)]"
            >
              {@final[stat]}
            </dd>
          </div>
        </dl>
        <p class="text-xs text-[var(--paper-muted)]">
          Stats: {confidence_text(@labels["stats"])} · Skills: {confidence_text(@labels["skills"])}
        </p>
        <p id="draft-skills" class="text-sm text-[var(--paper-ink)]">
          <span class="play-label">Skills</span>
          {Enum.map_join(@skills, ", ", fn {skill, level} -> "#{label(skill)} #{level}" end)}
        </p>
        <div class="flex items-center justify-between gap-3">
          <button
            type="button"
            id="rewrite"
            phx-click="rewrite"
            class="rounded border border-[var(--paper-rule)] px-4 py-2 font-medium text-[var(--paper-ink)] hover:opacity-80"
          >
            Write again
          </button>
          <button
            type="button"
            id="approve"
            phx-click="approve"
            class="rounded bg-[var(--paper-accent)] px-4 py-2 font-medium text-[var(--paper-on-accent)] hover:opacity-90"
          >
            Approve the draft
          </button>
        </div>
      </div>

      <button
        type="button"
        phx-click="go"
        phx-value-step="origin"
        class="rounded border border-[var(--paper-rule)] px-4 py-2 font-medium text-[var(--paper-ink)] hover:opacity-80"
      >
        Back
      </button>
    </section>
    """
  end

  defp draft_value(draft, "name"), do: if(draft.name == "", do: "—", else: draft.name)
  defp draft_value(draft, "class"), do: class_label(draft.class)
  defp draft_value(draft, "occupation"), do: label(draft.occupation || "laborer")
  defp draft_value(draft, "race"), do: label(draft.race)

  # A label below the confidence limit keeps the rules default.
  defp confidence_text(%{confidence: c}) do
    pct = round(c * 100)

    if c >= FromText.min_confidence(),
      do: "confidence #{pct}%",
      else: "default · confidence #{pct}%"
  end

  defp confidence_text(_), do: "default"

  attr :draft, :map, required: true
  attr :options, :map, required: true
  attr :name_error, :string, default: nil

  defp name_step(assigns) do
    assigns =
      assigns
      |> assign(:final, CC.final_stats(assigns.draft))
      |> assign(
        :skills,
        assigns.draft |> CC.skill_levels() |> Enum.sort_by(fn {s, l} -> {-l, s} end)
      )
      |> assign(:stat_names, @stats)

    ~H"""
    <section id="name-step" class="space-y-4">
      <.form
        for={%{}}
        as={:character}
        id="name-form"
        phx-change="name"
        phx-submit="begin"
        class="space-y-4"
      >
        <div class="play-panel space-y-2 rounded-lg px-4 py-3">
          <label for="character-name" class="play-label">Name</label>
          <input
            id="character-name"
            name="name"
            type="text"
            value={@draft.name}
            maxlength={@options.name_max_length + 10}
            autocomplete="off"
            placeholder="Type your character's name"
            aria-invalid={@name_error && "true"}
            aria-describedby={@name_error && "name-error"}
            class="w-full rounded border border-[var(--paper-rule)] bg-[var(--paper-bg)] px-3 py-2 text-[var(--paper-ink)] placeholder:text-[var(--paper-muted)] focus:border-[var(--paper-accent)] focus:outline-none"
          />
          <p :if={@name_error} id="name-error" class="text-sm text-[var(--paper-danger-ink)]">
            {@name_error}
          </p>
        </div>

        <div id="summary" class="play-panel space-y-3 rounded-lg px-4 py-3">
          <p class="font-serif text-lg font-semibold text-[var(--paper-ink)]">
            {if @draft.name == "", do: "Your character", else: @draft.name}
          </p>
          <p class="text-sm text-[var(--paper-muted)]">
            {label(@draft.race)} · {class_label(@draft.class)} · former {String.downcase(
              label(@draft.occupation)
            )}
          </p>
          <dl class="grid grid-cols-3 gap-2 sm:grid-cols-6">
            <div
              :for={{stat, _name} <- @stat_names}
              class="rounded bg-[var(--paper-margin)] px-2 py-1 text-center"
            >
              <dt class="play-label">{stat}</dt>
              <dd class="font-serif text-lg font-semibold text-[var(--paper-ink)]">{@final[stat]}</dd>
            </div>
          </dl>
          <p :if={@skills != []} id="summary-skills" class="text-sm text-[var(--paper-ink)]">
            <span class="play-label">Skills</span>
            {Enum.map_join(@skills, ", ", fn {skill, level} -> "#{label(skill)} #{level}" end)}
          </p>
        </div>

        <div class="flex items-center justify-between gap-3">
          <button
            type="button"
            phx-click="go"
            phx-value-step={if @draft.model == "from_text", do: "describe", else: "skills"}
            class="rounded border border-[var(--paper-rule)] px-4 py-2 font-medium text-[var(--paper-ink)] hover:opacity-80"
          >
            Back
          </button>
          <button
            type="submit"
            id="begin"
            phx-disable-with="Starting…"
            class="rounded bg-[var(--paper-accent)] px-4 py-2 font-medium text-[var(--paper-on-accent)] hover:opacity-90"
          >
            Begin adventure
          </button>
        </div>
      </.form>
    </section>
    """
  end

  attr :back, :string, default: nil
  attr :next, :string, required: true
  attr :next_disabled, :boolean, default: false

  defp step_nav(assigns) do
    ~H"""
    <div class="flex items-center justify-between gap-3">
      <button
        :if={@back}
        type="button"
        phx-click="go"
        phx-value-step={@back}
        class="rounded border border-[var(--paper-rule)] px-4 py-2 font-medium text-[var(--paper-ink)] hover:opacity-80"
      >
        Back
      </button>
      <span :if={!@back}></span>
      <button
        type="button"
        id={"next-#{@next}"}
        phx-click="go"
        phx-value-step={@next}
        disabled={@next_disabled}
        class="rounded bg-[var(--paper-accent)] px-4 py-2 font-medium text-[var(--paper-on-accent)] hover:opacity-90 disabled:opacity-40"
      >
        Next
      </button>
    </div>
    """
  end

  # Rule messages are lower-case fragments; on screen they start with a capital.
  defp sentence(<<first::utf8, rest::binary>>), do: String.upcase(<<first::utf8>>) <> rest

  defp label(id), do: id |> String.replace("_", " ") |> String.capitalize()

  defp class_label("none"), do: "No class"
  defp class_label(id), do: label(id)

  defp signed(0), do: "—"
  defp signed(n) when n > 0, do: "+#{n}"
  defp signed(n), do: "#{n}"
end
