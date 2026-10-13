defmodule TalesForgeWeb.AdminLive.CanonReviewLive.Show do
  @moduledoc """
  Founder tools: the session-versus-canon review of one session.

  The page does no review on mount. A founder clicks "Start the review",
  and the page then calls `TalesForge.Canon.review/1`. Each row has three
  actions: "Keep as session-only", "Add to canon" and "Mark as error".
  `TalesForge.Canon.decide/4` stores the decision with the founder email.
  No action changes the session or the seed files. "Add to canon" shows the
  proposed seed patch for a pull request.
  """

  use TalesForgeWeb, :live_view

  import TalesForgeWeb.AdminComponents

  alias TalesForge.Admin
  alias TalesForge.Canon

  @action_labels %{
    "session_only" => "Kept as session-only",
    "add_to_canon" => "Added to canon (seed patch proposed)",
    "error" => "Marked as error"
  }

  @impl true
  def mount(%{"id" => id}, _session, socket) do
    session = Admin.get_session!(id)

    {:ok,
     socket
     |> assign(:page_title, "Canon review · #{session.name}")
     |> assign(:session, session)
     |> assign(:review, nil)
     |> assign(:decisions, Canon.decisions(session.id))
     |> assign(:admin_email, socket.assigns[:admin_email])}
  end

  @impl true
  def handle_event("start_review", _params, socket) do
    review = Canon.review(socket.assigns.session)

    {:noreply,
     socket
     |> assign(:review, review)
     |> assign(:decisions, review.decisions)
     |> label_notice(review.labels)}
  end

  def handle_event("decide", %{"key" => key, "action" => action}, socket) do
    with %{admin_email: founder} when is_binary(founder) <- socket.assigns,
         %{differences: differences} <- socket.assigns.review,
         %{} = difference <- Enum.find(differences, &(&1.key == key)),
         {:ok, decision} <- Canon.decide(socket.assigns.session, difference, action, founder) do
      {:noreply,
       socket
       |> update(:decisions, &Map.put(&1, key, decision))
       |> put_flash(:info, Map.fetch!(@action_labels, action) <> ".")}
    else
      _ -> {:noreply, put_flash(socket, :error, "Only a signed-in founder can decide on a row.")}
    end
  end

  defp label_notice(socket, :error),
    do: put_flash(socket, :error, "Jev labels are not available. The rows show without a label.")

  defp label_notice(socket, :ok), do: socket

  @impl true
  def render(assigns) do
    assigns = assign(assigns, :action_labels, @action_labels)

    ~H"""
    <Layouts.admin socket={@socket} flash={@flash} active="canon_review" page={@session.name}>
      <header class="space-y-2">
        <.link navigate={~p"/admin/founders/canon-review"} class="text-sm text-[var(--paper-accent)]">
          ← Sessions
        </.link>
        <h2 class="font-serif text-2xl font-bold text-[var(--paper-ink)]">
          Session versus canon: {@session.name}
        </h2>
        <p class="text-sm text-[var(--paper-muted)]">
          Canon is the world seed in the repo. The review compares this session with its seed.
          A decision changes neither the session nor the seed files.
        </p>
      </header>

      <button
        id="start-review"
        phx-click="start_review"
        class="rounded bg-[var(--paper-accent)] px-3 py-1.5 text-sm text-[var(--paper-on-accent)]"
      >
        {if @review, do: "Run the review again", else: "Start the review"}
      </button>

      <.section_card :if={@review} title={"Differences (#{length(@review.differences)})"}>
        <p :if={@review.differences == []} id="canon-review-empty" class="text-sm">
          The session agrees with its seed.
        </p>
        <ul id="canon-review-rows" class="divide-y divide-[var(--paper-rule)] text-sm">
          <li :for={d <- @review.differences} id={"diff-#{d.key}"} class="space-y-2 py-3">
            <div>
              <span class="font-mono text-xs text-[var(--paper-muted)]">{d.kind}</span>
              <span :if={d.label} class="font-mono text-xs">· label {d.label}</span>
            </div>
            <p>{d.summary}</p>
            <div class="flex flex-wrap gap-2">
              <button
                :for={
                  {action, text} <- [
                    {"session_only", "Keep as session-only"},
                    {"add_to_canon", "Add to canon"},
                    {"error", "Mark as error"}
                  ]
                }
                phx-click="decide"
                phx-value-key={d.key}
                phx-value-action={action}
                class="rounded border border-[var(--paper-rule)] px-2 py-1 text-xs"
              >
                {text}
              </button>
            </div>
            <div :if={decision = @decisions[d.key]} class="text-xs text-[var(--paper-muted)]">
              <p class="decision">
                {@action_labels[decision.action]} by {decision.founder}
              </p>
              <pre
                :if={decision.seed_patch}
                class="seed-patch mt-1 whitespace-pre-wrap rounded bg-[var(--paper-rule)]/30 p-2 font-mono"
              >{decision.seed_patch}</pre>
            </div>
          </li>
        </ul>
      </.section_card>
    </Layouts.admin>
    """
  end
end
