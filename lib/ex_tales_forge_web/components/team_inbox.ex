defmodule TalesForgeWeb.TeamInbox do
  @moduledoc """
  The inbox panel on `/team` (`#inbox`), under New idea on the idea board
  (`TalesForgeWeb.TeamIdeaBoard`). Only a founder with inbox rules
  (`Workflow.Inbox.has_inbox?/2`) sees it. The rules and the queue are in
  `Workflow.Inbox`; the rows are in `Workflow.Inbox.Store`.

  The panel shows one item at a time:

    * With no open items, the panel shows an "Inbox zero" link. Otherwise it
      shows the count.
    * A context chip names the source (the card or the team chat). It shows a
      preview on hover and opens inline on tap.
    * Keys (the `TeamInbox` hook in `assets/js/team_hooks.js`): `a` approves,
      `Enter` gives the focus to the answer field, `Enter` in the field sends
      the answer, `Shift+Enter` adds a new line, `d` discards, `e` marks the
      item done, `s` skips (the item goes to the end of the queue), and `j`
      and `k` move to the next and to the previous item.
    * On a phone, swipe right to approve (or to mark the item done) and
      swipe left to skip.

  Each action applies after the undo time (`undo_ms`, 5 seconds). During
  that time a toast shows the action and an Undo button. Thus an undo never
  reverts a change that woke a bot.

  An answer goes through the source: `TalesForge.Board.add_comment/4` for a
  card and `TalesForge.Chat.post/3` for the team chat. An approval goes
  through `TalesForge.Board.answer_pr/4`, the same as Approve on the card.
  The answer or the approval closes the item (`Workflow.Inbox.closes/2`).
  """

  use TalesForgeWeb, :live_component

  alias TalesForge.Board
  alias TalesForge.Chat
  alias Workflow.Inbox
  alias Workflow.Inbox.Store

  @undo_ms 5_000

  @impl true
  def update(%{commit: ref}, socket), do: {:ok, commit(socket, ref)}
  def update(%{refresh: true}, socket), do: {:ok, load(socket)}

  def update(assigns, socket) do
    {:ok,
     socket
     |> assign(assigns)
     |> assign_new(:undo_ms, fn ->
       Application.get_env(:ex_tales_forge, :inbox_undo_ms, @undo_ms)
     end)
     |> assign_new(:index, fn -> 0 end)
     |> assign_new(:pending, fn -> nil end)
     |> assign(:handle, Chat.handle_for(assigns[:login] || socket.assigns[:login]))
     |> load()}
  end

  defp load(socket) do
    pending_id = socket.assigns.pending && socket.assigns.pending.id

    items =
      socket.assigns.handle
      |> Store.open()
      |> Enum.reject(&(&1.id == pending_id))

    socket
    |> assign(:items, items)
    |> assign(:index, min(socket.assigns.index, max(length(items) - 1, 0)))
  end

  defp current(%{items: items, index: index}), do: Enum.at(items, index)

  @impl true
  def handle_event("key", %{"key" => key}, socket) do
    case current(socket.assigns) do
      nil -> {:noreply, socket}
      item -> {:noreply, act(socket, item, Inbox.key_action(key, item.kind), nil)}
    end
  end

  def handle_event("act", %{"action" => action}, socket),
    do: handle_action(socket, String.to_existing_atom(action), nil)

  def handle_event("swipe", %{"dir" => "right"}, socket) do
    case current(socket.assigns) do
      %{kind: :approve} -> handle_action(socket, :approve, nil)
      _item -> handle_action(socket, :done, nil)
    end
  end

  def handle_event("swipe", %{"dir" => "left"}, socket), do: handle_action(socket, :skip, nil)

  def handle_event("answer", %{"answer" => text}, socket) do
    case String.trim(text) do
      "" -> {:noreply, socket}
      text -> handle_action(socket, :answer, text)
    end
  end

  def handle_event("undo", _params, socket) do
    {:noreply, socket |> assign(:pending, nil) |> load()}
  end

  def handle_event(_event, _params, socket), do: {:noreply, socket}

  defp handle_action(socket, action, text) do
    case current(socket.assigns) do
      nil -> {:noreply, socket}
      item -> {:noreply, act(socket, item, action, text)}
    end
  end

  defp act(socket, _item, nil, _text), do: socket

  defp act(socket, _item, dir, _text) when dir in [:next, :prev],
    do:
      assign(socket, :index, Inbox.step(socket.assigns.index, dir, length(socket.assigns.items)))

  defp act(socket, _item, :answer, nil), do: push_event(socket, "inbox:focus", %{})
  defp act(socket, %{kind: kind}, :approve, _text) when kind != :approve, do: socket

  defp act(socket, item, action, text) do
    ref = System.unique_integer([:positive])

    send_update_after(
      self(),
      __MODULE__,
      %{id: socket.assigns.id, commit: ref},
      socket.assigns.undo_ms
    )

    socket
    |> commit_pending()
    |> assign(:pending, %{ref: ref, id: item.id, item: item, action: action, text: text})
    |> load()
  end

  # A new action applies the action that waits now.
  defp commit_pending(%{assigns: %{pending: %{ref: ref}}} = socket), do: commit(socket, ref)
  defp commit_pending(socket), do: socket

  defp commit(%{assigns: %{pending: %{ref: ref} = pending}} = socket, ref) do
    unless read_only?(socket.assigns), do: apply_action(socket.assigns, pending)
    socket |> assign(:pending, nil) |> load()
  end

  defp commit(socket, _ref), do: socket

  defp read_only?(assigns), do: assigns[:read_only] == true or assigns[:qa] == true

  defp apply_action(%{handle: handle}, %{id: id, action: :skip}), do: Store.skip(id, handle)

  defp apply_action(assigns, %{action: :answer, item: item, text: text}) do
    send_answer(assigns, item, text)
    Store.close_item(item.id, assigns.handle, :answer)
  end

  defp apply_action(assigns, %{action: :approve, item: item}) do
    with %Board.Idea{} = idea <- Board.get_idea(item.idea_id),
         {:ok, _} <- Board.answer_pr(idea, assigns.founder, :approve, nil),
         do: Store.close_item(item.id, assigns.handle, :approve)
  end

  defp apply_action(%{handle: handle}, %{id: id, action: action}),
    do: Store.close_item(id, handle, action)

  defp send_answer(assigns, %{source: :chat}, text),
    do: Chat.post(assigns.founder, text, login: assigns.login)

  defp send_answer(assigns, %{source: :comment, idea_id: idea_id}, text) do
    with %Board.Idea{} = idea <- Board.get_idea(idea_id),
         do: Board.add_comment(idea, assigns.founder, text, login: assigns.login)
  end

  @doc """
  The toast text of an action.

      iex> TalesForgeWeb.TeamInbox.toast(:skip)
      "Skipped. The item moves to the end of the queue."
  """
  @spec toast(atom()) :: String.t()
  def toast(:approve), do: "Approved."
  def toast(:answer), do: "Answer sent."
  def toast(:done), do: "Marked done."
  def toast(:discard), do: "Discarded."
  def toast(:skip), do: "Skipped. The item moves to the end of the queue."

  @doc """
  The label of the context chip of an item.

      iex> TalesForgeWeb.TeamInbox.chip(%{source: :chat, title: nil})
      "Team chat"
      iex> TalesForgeWeb.TeamInbox.chip(%{source: :comment, title: "Dark mode"})
      "Card: Dark mode"
      iex> TalesForgeWeb.TeamInbox.chip(%{source: :pr, title: "Dark mode"})
      "PR on card: Dark mode"
  """
  @spec chip(map()) :: String.t()
  def chip(%{source: :chat}), do: "Team chat"
  def chip(%{source: :pr, title: title}) when is_binary(title), do: "PR on card: " <> title
  def chip(%{title: title}) when is_binary(title), do: "Card: " <> title
  def chip(_item), do: "Card"

  defp ask(:answer), do: "asks for an answer"
  defp ask(:approve), do: "asks for your OK"
  defp ask(_kind), do: "for you"

  defp who("bot:" <> bot), do: String.capitalize(bot)
  defp who(email) when is_binary(email), do: email |> String.split("@") |> hd()
  defp who(_), do: "someone"

  @impl true
  def render(assigns) do
    assigns = assign(assigns, :item, current(assigns))

    ~H"""
    <section
      id={@id}
      phx-hook="TeamInbox"
      phx-target={@myself}
      aria-labelledby={"#{@id}-title"}
      class="team-card grid gap-3 rounded-xl p-4"
      data-count={length(@items)}
    >
      <h3 id={"#{@id}-title"} class="text-sm font-semibold">
        <%= if @items == [] and is_nil(@pending) do %>
          <a id="inbox-zero" href={"##{@id}"} class="underline">Inbox zero</a>
        <% else %>
          Inbox
          <span class="badge badge-primary badge-sm ml-1" data-role="inbox-count">
            {length(@items)}
          </span>
        <% end %>
      </h3>

      <article
        :if={@item}
        id="inbox-item"
        data-item-id={@item.id}
        data-kind={@item.kind}
        data-swipe
        class="grid gap-2"
      >
        <details id="inbox-chip" class="group relative">
          <summary
            title={String.slice(@item.body, 0, 200)}
            class="inline-flex min-h-11 cursor-pointer items-center rounded-full border px-3 text-sm"
          >
            {chip(@item)}
          </summary>
          <div
            role="tooltip"
            class="pointer-events-none absolute z-10 mt-1 hidden max-w-sm rounded border bg-[var(--paper-panel)] p-2 text-xs shadow group-hover:block group-open:hidden"
          >
            {String.slice(@item.body, 0, 200)}
          </div>
          <div id="inbox-chip-body" class="mt-2 grid gap-1 rounded border p-2 text-sm">
            <p class="whitespace-pre-line">{@item.body}</p>
            <a href={@item.url} class="underline">
              {if @item.source == :chat, do: "Open the team chat", else: "Open the card"}
            </a>
          </div>
        </details>

        <p class="text-sm">
          <span class="font-semibold">{who(@item.author)}</span>
          <span class="text-[var(--paper-muted)]">
            {ask(@item.kind)}
          </span>
        </p>
        <p id="inbox-item-body" class="line-clamp-3 whitespace-pre-line text-sm">{@item.body}</p>

        <form
          :if={@item.kind == :answer}
          id="inbox-answer"
          phx-submit="answer"
          phx-target={@myself}
          class="grid gap-2"
        >
          <textarea
            id="inbox-answer-text"
            name="answer"
            rows="2"
            data-inbox-answer
            aria-label="Your answer"
            placeholder="Write an answer. Enter sends it. Shift+Enter adds a new line."
            class="textarea textarea-bordered w-full"
          ></textarea>
        </form>

        <div class="flex flex-wrap gap-2">
          <button
            :if={@item.kind == :approve}
            type="button"
            id="inbox-approve"
            phx-click="act"
            phx-value-action="approve"
            phx-target={@myself}
            class="btn btn-primary btn-sm min-h-11"
          >
            Approve (a)
          </button>
          <button
            :if={@item.kind == :answer}
            type="submit"
            form="inbox-answer"
            id="inbox-send"
            class="btn btn-primary btn-sm min-h-11"
          >
            Send (Enter)
          </button>
          <button
            type="button"
            id="inbox-done"
            phx-click="act"
            phx-value-action="done"
            phx-target={@myself}
            class="btn btn-sm min-h-11"
          >
            Done (e)
          </button>
          <button
            type="button"
            id="inbox-skip"
            phx-click="act"
            phx-value-action="skip"
            phx-target={@myself}
            class="btn btn-sm min-h-11"
          >
            Skip (s)
          </button>
          <button
            type="button"
            id="inbox-discard"
            phx-click="act"
            phx-value-action="discard"
            phx-target={@myself}
            class="btn btn-ghost btn-sm min-h-11"
          >
            Discard (d)
          </button>
        </div>
        <p class="text-xs text-[var(--paper-muted)]">
          Item {@index + 1} of {length(@items)}. Use j and k to move between items.
        </p>
      </article>

      <div
        :if={@pending}
        id="inbox-toast"
        role="status"
        aria-live="polite"
        class="flex items-center gap-3 rounded border px-3 py-2 text-sm"
      >
        <span>{toast(@pending.action)}</span>
        <button
          type="button"
          id="inbox-undo"
          phx-click="undo"
          phx-target={@myself}
          class="btn btn-sm min-h-11"
        >
          Undo
        </button>
      </div>
    </section>
    """
  end
end
