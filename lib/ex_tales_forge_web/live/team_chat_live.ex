defmodule TalesForgeWeb.TeamChatLive do
  @moduledoc """
  The team chat panel (`TalesForge.Chat`), opened from the header: the
  "Chat" button next to the who-is-online counter, or the "Chat" button on a
  person in that list (the message box then starts with their `@handle`).
  Nested in `TalesForgeWeb.OnlineHeaderLive`, which loads it through config
  `:team_chat_live` on production and locally.

  - The chat button shows the unread count of `TalesForge.Chat.unread/1`
    (your handle comes from your GitHub login, `TalesForge.Board.Mentions`).
  - Threads: the thread list is on the left, sorted by the last message, with
    the unread count of each thread. The open thread is on the right. On a
    phone, the panel shows the list or the open thread, and "Threads" goes
    back to the list. "New thread" starts a subject thread, and "1:1"
    starts a direct thread with one other founder.
  - The server keeps the open thread. Each event checks the thread again
    (`TalesForge.Chat.thread/2`), and a post goes only to the open thread.
  - Accessible: the panel is a `role="dialog"` with a title; focus moves to
    the message box when it opens; Esc or "Close" closes it and moves focus
    back to the chat button. New messages are announced (`aria-live`).
  - The panel is rendered at the end of `<body>` (`portal`), so the header's
    blur does not trap it: an opaque, full-height drawer above the page.
    Messages are bubbles (avatar, name, time), newest at the bottom, and the
    list scrolls down by itself (`TeamChat` hook in `assets/js/team_hooks.js`).
  - Composer pinned to the bottom: a one-line box that grows, Enter sends,
    Shift+Enter adds a new line; typing @ suggests names (`MentionSuggest`).
  - Images (`TalesForge.Images`, `TalesForgeWeb.TeamImages`): paste, drop or
    pick PNG, JPEG or WebP files, or "Capture screen" (one still of a tab,
    window or screen; desktop only). The chosen images show as previews above
    the message box; the text is the note and can be empty. Sent images show
    as thumbnails that open the full image.
  - Phone: the panel fills the screen; from `sm` up it is a side panel.
  """

  use TalesForgeWeb, :live_view

  alias Phoenix.LiveView.JS
  alias TalesForge.Chat
  alias TalesForge.Chat.Message
  alias TalesForge.TeamOnline
  alias TalesForgeWeb.TeamImages

  @impl true
  @spec mount(map(), map(), Phoenix.LiveView.Socket.t()) ::
          {:ok, Phoenix.LiveView.Socket.t(), keyword()}
  def mount(_params, session, socket) do
    login = socket.assigns[:admin_github_login]
    viewer = Chat.viewer(socket.assigns[:admin_email], login)

    if connected?(socket) do
      Chat.subscribe(viewer)
      if socket.parent_pid, do: send(socket.parent_pid, {:team_chat_pid, self()})
    end

    {:ok,
     socket
     |> assign(:id_prefix, session["id_prefix"] || "chat")
     |> assign(:login, login)
     |> assign(:email, socket.assigns[:admin_email])
     |> assign(:me, Chat.handle_for(login))
     |> assign(:viewer, viewer)
     |> assign(:thread, nil)
     |> assign(:threads, [])
     |> assign(:counts, %{})
     |> assign(:pane, :thread)
     |> assign(:subject_form, to_form(%{"subject" => ""}, as: :thread))
     |> assign(:open, false)
     |> assign(:draft, "")
     |> assign(:messages, [])
     |> assign(:unread, Chat.unread(login))
     |> assign(:form, to_form(%{"body" => ""}, as: :chat))
     |> TeamImages.allow(:chat_images), layout: false}
  end

  @impl true
  @spec handle_event(String.t(), map(), Phoenix.LiveView.Socket.t()) ::
          {:noreply, Phoenix.LiveView.Socket.t()}
  def handle_event("open", _params, socket), do: {:noreply, open(socket, nil)}

  def handle_event("open_thread", %{"id" => id}, socket), do: {:noreply, view_thread(socket, id)}
  def handle_event("threads", _params, socket), do: {:noreply, assign(socket, :pane, :list)}

  def handle_event("new_subject", params, socket) do
    case Chat.start_subject(socket.assigns.viewer, get_in(params, ["thread", "subject"])) do
      {:ok, thread} ->
        {:noreply,
         socket
         |> assign(:subject_form, to_form(%{"subject" => ""}, as: :thread))
         |> view_thread(thread.id)}

      {:error, %Ecto.Changeset{} = cs} ->
        {:noreply, assign(socket, :subject_form, to_form(cs, as: :thread))}

      {:error, :forbidden} ->
        {:noreply, socket}
    end
  end

  def handle_event("new_direct", %{"handle" => handle}, socket) do
    case Chat.start_direct(socket.assigns.viewer, handle) do
      {:ok, thread} -> {:noreply, view_thread(socket, thread.id)}
      {:error, :forbidden} -> {:noreply, socket}
    end
  end

  def handle_event("close", _params, socket), do: {:noreply, assign(socket, :open, false)}

  def handle_event("validate", _params, socket), do: {:noreply, socket}

  def handle_event("cancel_image", %{"ref" => ref}, socket),
    do: {:noreply, cancel_upload(socket, :chat_images, ref)}

  def handle_event("send", params, socket) do
    body = get_in(params, ["chat", "body"]) || ""
    images = TeamImages.read_all(socket, :chat_images)

    opts = [login: socket.assigns.login, images: images, thread_id: thread_id(socket)]

    case Chat.post(socket.assigns.admin_email, body, opts) do
      {:ok, _message} ->
        {:noreply,
         socket
         |> assign(:form, to_form(%{"body" => ""}, as: :chat))
         |> push_event("team_chat:sent", %{})}

      {:error, %Ecto.Changeset{} = changeset} ->
        {:noreply, assign(socket, :form, to_form(changeset, as: :chat))}

      {:error, :not_found} ->
        {:noreply, view_thread(socket, nil)}
    end
  end

  defp thread_id(%{assigns: %{thread: %{id: id}}}), do: id
  defp thread_id(_socket), do: nil

  @impl true
  @spec handle_info(term(), Phoenix.LiveView.Socket.t()) ::
          {:noreply, Phoenix.LiveView.Socket.t()}
  def handle_info({:open_chat, to}, socket), do: {:noreply, open(socket, to)}

  def handle_info({:team_chat, %Message{} = m}, socket) do
    if socket.assigns.open and open_thread?(socket, m) do
      unless socket.assigns[:qa], do: Chat.mark_read(socket.assigns.login, m.thread_id)
      {:noreply, socket |> assign(:messages, socket.assigns.messages ++ [m]) |> load_threads()}
    else
      {:noreply, socket |> assign(:unread, Chat.unread(socket.assigns.login)) |> load_threads()}
    end
  end

  def handle_info({:team_chat_thread, _thread}, socket), do: {:noreply, load_threads(socket)}

  def handle_info(_msg, socket), do: {:noreply, socket}

  # The server checks the thread again on each PubSub message.
  defp open_thread?(%{assigns: %{thread: %{id: id}, viewer: viewer}}, %Message{thread_id: id}),
    do: match?({:ok, _}, Chat.thread(viewer, id))

  defp open_thread?(_socket, _message), do: false

  defp open(socket, to) do
    body = if to, do: "@#{mention(to)} ", else: ""

    socket
    |> assign(:open, true)
    |> view_thread(nil)
    |> assign(:form, to_form(%{"body" => body}, as: :chat))
  end

  # Opens the thread `id` (nil is General) when the viewer can read it, else
  # General. The QA session never marks a thread as read for anyone.
  defp view_thread(socket, id) do
    viewer = socket.assigns.viewer

    {thread, messages} =
      with {:error, :not_found} <- load(viewer, id),
           {:error, :not_found} <- load(viewer, nil) do
        {nil, []}
      end

    unless socket.assigns[:qa] == true or is_nil(thread),
      do: Chat.mark_read(socket.assigns.login, thread.id)

    socket
    |> assign(thread: thread, messages: messages, pane: :thread)
    |> assign(:unread, Chat.unread(socket.assigns.login))
    |> load_threads()
  end

  defp load(viewer, id) do
    with {:ok, thread} <- Chat.thread(viewer, id),
         {:ok, messages} <- Chat.recent(viewer, thread.id),
         do: {thread, messages}
  end

  defp load_threads(%{assigns: %{open: false}} = socket), do: socket

  defp load_threads(%{assigns: %{viewer: viewer}} = socket) do
    socket
    |> assign(:threads, Chat.threads(viewer))
    |> assign(:counts, Chat.unread_by_thread(viewer, socket.assigns.email))
  end

  # The handle to start a message with: "bot:<name>", a founder's @handle
  # (from their GitHub login) or, without one, their email.
  defp mention("bot:" <> bot), do: bot

  defp mention(to) do
    if String.contains?(to, "@"),
      do: Chat.handle_for_email(to) || to |> String.split("@") |> hd(),
      else: to
  end

  @impl true
  @spec render(map()) :: Phoenix.LiveView.Rendered.t()
  def render(assigns) do
    ~H"""
    <div id={"#{@id_prefix}-root"} class="contents">
      <button
        id={"#{@id_prefix}-button"}
        type="button"
        phx-click="open"
        aria-haspopup="dialog"
        aria-expanded={to_string(@open)}
        aria-controls={"#{@id_prefix}-panel"}
        class="relative inline-flex min-h-9 items-center gap-1 rounded-full border border-[var(--paper-rule)] px-2.5 py-1 text-xs font-semibold text-[var(--paper-ink)] hover:bg-[var(--paper-bg)] focus-visible:outline-2 focus-visible:outline-[var(--paper-accent)] sm:text-sm"
      >
        <.icon name="hero-chat-bubble-left-right" class="size-4" />
        <span>Chat</span>
        <span
          :if={@unread > 0}
          id={"#{@id_prefix}-unread"}
          class="ml-0.5 rounded-full bg-[var(--paper-accent)] px-1.5 text-[0.7rem] leading-5 text-white"
        >
          {@unread}<span class="sr-only"> new mentions of you</span>
        </span>
      </button>

      <.portal :if={@open} id={"#{@id_prefix}-portal"} target="body">
        <div
          id={"#{@id_prefix}-backdrop"}
          class="fixed inset-0 z-[90] hidden bg-black/30 sm:block"
          phx-click={
            JS.push("close", target: "##{@id_prefix}-root") |> JS.focus(to: "##{@id_prefix}-button")
          }
          aria-hidden="true"
        >
        </div>
        <div
          id={"#{@id_prefix}-panel"}
          role="dialog"
          aria-modal="true"
          aria-labelledby={"#{@id_prefix}-title"}
          phx-hook="TeamChat"
          phx-window-keydown={
            JS.push("close", target: "##{@id_prefix}-root") |> JS.focus(to: "##{@id_prefix}-button")
          }
          phx-key="Escape"
          class="team-chat-panel fixed inset-y-0 right-0 z-[100] flex h-dvh w-full flex-col bg-[var(--paper-panel)] text-left text-[var(--paper-ink)] shadow-2xl sm:w-[44rem] sm:border-l sm:border-[var(--paper-rule)]"
          style="background-color: var(--paper-panel, #fbf6ec);"
        >
          <header class="flex shrink-0 items-center justify-between gap-2 border-b border-[var(--paper-rule)] px-4 py-2">
            <h2 id={"#{@id_prefix}-title"} class="font-serif text-lg font-semibold">Team chat</h2>
            <button
              :if={@pane == :thread}
              id={"#{@id_prefix}-threads-button"}
              type="button"
              phx-click="threads"
              phx-target={"##{@id_prefix}-root"}
              class="min-h-11 rounded-full border border-[var(--paper-rule)] px-3 text-sm font-semibold sm:hidden"
            >
              Threads
            </button>
            <button
              id={"#{@id_prefix}-close"}
              type="button"
              phx-click={
                JS.push("close", target: "##{@id_prefix}-root")
                |> JS.focus(to: "##{@id_prefix}-button")
              }
              aria-label="Close the chat"
              class="inline-flex size-11 items-center justify-center rounded-full hover:bg-[var(--paper-bg)]"
            >
              <.icon name="hero-x-mark" class="size-5" />
            </button>
          </header>

          <div class="flex min-h-0 flex-1">
            <nav
              id={"#{@id_prefix}-threads"}
              aria-label="Threads"
              class={[
                "min-h-0 w-full shrink-0 flex-col overflow-y-auto border-[var(--paper-rule)] sm:flex sm:w-56 sm:border-r",
                if(@pane == :list, do: "flex", else: "hidden")
              ]}
            >
              <ul class="flex-1">
                <li :for={t <- @threads}>
                  <button
                    id={"#{@id_prefix}-thread-#{t.id}"}
                    type="button"
                    phx-click="open_thread"
                    phx-value-id={t.id}
                    phx-target={"##{@id_prefix}-root"}
                    aria-current={if(@thread && @thread.id == t.id, do: "true")}
                    class={[
                      "flex min-h-11 w-full items-center gap-2 px-3 py-2 text-left text-sm hover:bg-[var(--paper-bg)]",
                      @thread && @thread.id == t.id && "bg-[var(--paper-bg)] font-semibold"
                    ]}
                  >
                    <.icon
                      name={if(t.kind == "direct", do: "hero-user", else: "hero-hashtag")}
                      class="size-4 shrink-0"
                    />
                    <span class="min-w-0 flex-1 truncate">{Chat.title(t, @viewer)}</span>
                    <span
                      :if={Map.get(@counts, t.id, 0) > 0}
                      id={"#{@id_prefix}-thread-#{t.id}-unread"}
                      class="rounded-full bg-[var(--paper-accent)] px-1.5 text-[0.7rem] leading-5 text-white"
                    >
                      {Map.get(@counts, t.id)}<span class="sr-only"> unread</span>
                    </span>
                  </button>
                </li>
              </ul>
              <.form
                :if={match?({:founder, _}, @viewer)}
                for={@subject_form}
                id={"#{@id_prefix}-new-thread"}
                phx-submit="new_subject"
                phx-target={"##{@id_prefix}-root"}
                class="border-t border-[var(--paper-rule)] p-2"
              >
                <label for={"#{@id_prefix}-subject"} class="text-xs font-semibold">New thread</label>
                <div class="mt-1 flex gap-1">
                  <input
                    id={"#{@id_prefix}-subject"}
                    name="thread[subject]"
                    value={@subject_form[:subject].value}
                    maxlength={TalesForge.Chat.Thread.max_subject()}
                    placeholder="Subject"
                    class="min-h-11 min-w-0 flex-1 rounded border border-[var(--paper-rule)] bg-[var(--paper-bg)] px-2 text-base"
                  />
                  <button
                    type="submit"
                    aria-label="Start the thread"
                    class="team-cta min-h-11 rounded px-3"
                  >
                    <.icon name="hero-plus" class="size-4" />
                  </button>
                </div>
                <p
                  :for={msg <- Enum.map(@subject_form[:subject].errors, &elem(&1, 0))}
                  class="pt-1 text-sm text-red-700"
                  role="alert"
                >
                  {msg}
                </p>
              </.form>
              <div
                :if={Chat.direct_choices(@viewer) != []}
                id={"#{@id_prefix}-new-direct"}
                class="border-t border-[var(--paper-rule)] p-2"
              >
                <p class="text-xs font-semibold">1:1</p>
                <div class="mt-1 flex flex-wrap gap-1">
                  <button
                    :for={{handle, name} <- Chat.direct_choices(@viewer)}
                    id={"#{@id_prefix}-direct-#{handle}"}
                    type="button"
                    phx-click="new_direct"
                    phx-value-handle={handle}
                    phx-target={"##{@id_prefix}-root"}
                    class="min-h-11 rounded-full border border-[var(--paper-rule)] px-3 text-sm"
                  >
                    {name}
                  </button>
                </div>
              </div>
            </nav>

            <section
              id={"#{@id_prefix}-open-thread"}
              aria-labelledby={"#{@id_prefix}-thread-title"}
              class={[
                "min-h-0 min-w-0 flex-1 flex-col sm:flex",
                if(@pane == :thread, do: "flex", else: "hidden")
              ]}
            >
              <h3
                :if={@thread}
                id={"#{@id_prefix}-thread-title"}
                class="shrink-0 border-b border-[var(--paper-rule)] px-4 py-1.5 text-sm font-semibold"
              >
                {Chat.title(@thread, @viewer)}
                <span :if={@thread.kind == "direct"} class="font-normal text-[var(--paper-muted)]">
                  · only the two of you can read this 1:1
                </span>
              </h3>
              <ol
                id={"#{@id_prefix}-messages"}
                data-chat-scroll
                aria-live="polite"
                aria-label="Messages"
                class="min-h-0 flex-1 space-y-3 overflow-y-auto overscroll-contain px-3 py-4"
              >
                <li
                  :if={@messages == []}
                  id={"#{@id_prefix}-empty"}
                  class="grid h-full place-items-center text-sm text-[var(--paper-muted)]"
                >
                  No messages yet
                </li>
                <li
                  :for={m <- @messages}
                  id={"#{@id_prefix}-msg-#{m.id}"}
                  class={["flex items-end gap-2", mine?(m, @email) && "flex-row-reverse"]}
                >
                  <.avatar author={m.author} />
                  <div class={[
                    "max-w-[80%] rounded-2xl px-3 py-2 text-sm leading-relaxed shadow-sm",
                    if(mine?(m, @email),
                      do: "rounded-br-sm bg-[#f3dcae] text-[#2b1d0e]",
                      else: "rounded-bl-sm border border-[var(--paper-rule)] bg-[var(--paper-bg)]"
                    ),
                    @me && @me in m.mentions && "ring-2 ring-[var(--paper-accent)]"
                  ]}>
                    <p class="flex flex-wrap items-baseline gap-x-2 text-xs">
                      <span class="font-semibold">{author(m.author)}</span>
                      <TalesForgeWeb.TeamTime.ago
                        at={m.inserted_at}
                        class="text-[var(--paper-muted)]"
                      />
                      <span
                        :if={@me && @me in m.mentions}
                        class="font-semibold text-[var(--paper-accent)]"
                      >
                        Mentions you
                      </span>
                    </p>
                    <p :if={m.body != ""} class="whitespace-pre-wrap break-words">{body(m.body)}</p>
                    <TeamImages.thumbnails
                      images={images(m)}
                      id={"#{@id_prefix}-msg-#{m.id}-images"}
                      class="mt-1"
                    />
                  </div>
                </li>
              </ol>

              <.form
                for={@form}
                id={"#{@id_prefix}-form"}
                data-draft="chat"
                phx-submit={JS.push("send", target: "##{@id_prefix}-root")}
                phx-change="validate"
                phx-target={"##{@id_prefix}-root"}
                phx-drop-target={@uploads.chat_images.ref}
                phx-hook="ImageInput"
                class="shrink-0 border-t border-[var(--paper-rule)] bg-[var(--paper-panel)] px-3 pb-[max(0.75rem,env(safe-area-inset-bottom))] pt-2"
              >
                <p
                  :for={msg <- Enum.map(@form[:body].errors, &elem(&1, 0))}
                  class="pb-1 text-sm text-red-700"
                  role="alert"
                >
                  {msg}
                </p>
                <TeamImages.picker
                  upload={@uploads.chat_images}
                  id={"#{@id_prefix}-images"}
                  target={"##{@id_prefix}-root"}
                />
                <div class="relative mt-2 flex items-end gap-2">
                  <label for={"#{@id_prefix}-body"} class="sr-only">Message</label>
                  <textarea
                    id={"#{@id_prefix}-body"}
                    phx-update="ignore"
                    name="chat[body]"
                    rows="1"
                    maxlength={Message.max_length()}
                    placeholder="Message or image note (@ to mention)"
                    phx-mounted={JS.focus()}
                    phx-hook="MentionSuggest"
                    data-handles={Jason.encode!(Chat.suggestions())}
                    data-chat-input
                    aria-autocomplete="list"
                    aria-controls={"#{@id_prefix}-mention-list"}
                    aria-describedby={"#{@id_prefix}-hint"}
                    class="max-h-40 min-h-11 flex-1 resize-none rounded-2xl border border-[var(--paper-rule)] bg-[var(--paper-bg)] px-3 py-2.5 text-base leading-snug"
                  >{Phoenix.HTML.Form.normalize_value("textarea", @form[:body].value)}</textarea>
                  <ul
                    id={"#{@id_prefix}-mention-list"}
                    role="listbox"
                    aria-label="Names to mention"
                    phx-update="ignore"
                    hidden
                    class="absolute bottom-full left-0 z-10 mb-1 max-h-48 overflow-y-auto rounded border border-[var(--paper-rule)] bg-[var(--paper-panel)] text-sm shadow"
                  >
                  </ul>
                  <button
                    id={"#{@id_prefix}-send"}
                    type="submit"
                    aria-label="Send"
                    class="team-cta inline-flex size-11 shrink-0 items-center justify-center rounded-full"
                  >
                    <.icon name="hero-paper-airplane" class="size-5" />
                  </button>
                </div>
                <p
                  id={"#{@id_prefix}-draft-hint"}
                  data-draft-hint
                  aria-live="polite"
                  phx-update="ignore"
                  class="text-xs font-semibold text-[var(--paper-accent)] empty:hidden"
                >
                </p>
                <p id={"#{@id_prefix}-hint"} class="sr-only">
                  Enter sends, Shift and Enter adds a new line. Write @ to mention a founder or a bot. Paste or drop an image to add it.
                </p>
              </.form>
            </section>
          </div>
        </div>
      </.portal>
    </div>
    """
  end

  # The message text with mentions highlighted, built here and not in the
  # template, so no template whitespace shows inside `whitespace-pre-wrap`.
  # Each part is escaped.
  defp body(text) do
    text
    |> Chat.segments()
    |> Enum.map(fn
      {:mention, t} ->
        ["<span class=\"font-semibold text-[var(--paper-accent)]\">", escape(t), "</span>"]

      {:text, t} ->
        escape(t)
    end)
    |> Phoenix.HTML.raw()
  end

  defp images(%Message{images: images}) when is_list(images), do: images
  defp images(_message), do: []

  defp escape(t), do: t |> Phoenix.HTML.html_escape() |> Phoenix.HTML.safe_to_string()

  defp mine?(m, email), do: is_binary(email) and m.author == email

  attr :author, :string, required: true

  defp avatar(%{author: "bot:" <> bot} = assigns) do
    assigns = assign(assigns, :bot, bot)

    ~H"""
    <img
      src={"/images/team/#{@bot}-avatar-96.jpg"}
      width="96"
      height="96"
      alt=""
      class="size-8 shrink-0 rounded-full border-2 border-[#b4874a] object-cover"
    />
    """
  end

  defp avatar(assigns) do
    ~H"""
    <span
      aria-hidden="true"
      class="grid size-8 shrink-0 place-items-center rounded-full border-2 border-[#b4874a] bg-[#f3dcae] text-sm font-bold text-[#3b2a16]"
    >
      {String.first(author(@author))}
    </span>
    """
  end

  defp author("bot:" <> bot = actor) do
    team = Workflow.Team.Source.team()

    case Workflow.Team.bot_id(team, actor) do
      nil -> String.capitalize(bot)
      id -> Workflow.Team.bot_name(team, id)
    end
  end

  defp author(email), do: TeamOnline.name(Workflow.Team.Source.team(), email)
end
