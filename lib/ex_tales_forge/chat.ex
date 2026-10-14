defmodule TalesForge.Chat do
  @moduledoc """
  The team chat (board card "Team chat with mentions", decision 2026-10-10):
  the room of the founders and the bots. It lives on production only, like
  the board (`TalesForge.AppRole` area `:board`).

  - The chat has threads (`TalesForge.Chat.Thread`). A subject thread is for
    all founders and bots. A direct thread is a 1:1 chat of two founders.
    The General thread holds the messages from the time before threads.
  - Each read, post, PubSub path and unread count gets a viewer
    (`TalesForge.Chat.ThreadRules.viewer/3`) and checks it with
    `TalesForge.Chat.ThreadRules.can_read?/2`. A thread that the viewer
    cannot read gives `{:error, :not_found}`, the same result as a thread
    that does not exist.
  - Messages are in `team_chat_messages` and arrive live over PubSub
    (`subscribe/1`). A direct message goes only to the topics of its two
    members. History stays (how long we keep it is a deferred question on
    the card).
  - Mentions use the board's one parser, `TalesForge.Board.Mentions`:
    `@<founder handle>`, `@founders`, `@<bot id>` and `@devops` (all bots of
    the team config, `Workflow.Team`).
  - The chat button shows the new messages for a founder (`bar/2`): the
    count and the latest message. A message counts when another author
    writes it in a thread that the founder takes part in (the participant
    rule, `TalesForge.Chat.ThreadRules.participants/4`), or in a direct
    thread of the founder. General uses the same rule. The count of a
    thread clears when the founder opens it (`mark_read/2`). No email or
    push (the founder's answer on the card).
  - A bot mention **by a founder** wakes the bot through the board's webhook
    outbox (`TalesForge.Board.Workers.Notify`, event `chat.mention`), in the
    same transaction as the message. A bot that mentions a bot wakes nobody,
    to keep bot costs under control (the founder's answer on the card).
  - A message that names a founder with inbox rules makes an item in that
    founder's inbox (`Workflow.Inbox`), in the same transaction. The
    message also counts on the chat button (`bar/2`). A message by that
    founder closes the chat items of that founder.
  - Each new message notifies the participants of its thread
    (`TalesForge.Chat.ThreadRules.participants/4`): the founder or bot that
    started the thread, posted in it, or was @mentioned in it. A founder
    gets an inbox item (rule `thread_message`). A bot gets a wake through
    the webhook outbox (event `chat.thread_message`, with `thread_id`). The
    author is not notified. A message by a bot wakes no bot. In a direct
    thread, only its two members are participants, and no bot wakes. A
    founder that the message names gets one item only (the `mention` item).
  - A message can carry images (`TalesForge.Images`): pasted, dropped,
    picked, or one still from "Capture screen". The text is then the note
    and can be empty. The bots get the image links in the JSON (`images`).
  - Bots read and write through `GET`/`POST /internal/chat` with their board
    tokens (`TalesForgeWeb.ChatApiController`, `api/3`).

  This module does IO, so it is an edge: it reads the team config from
  `Workflow.Team.Source`.
  """

  import Ecto.Query

  alias Ecto.Multi
  alias TalesForge.AppRole
  alias TalesForge.Board.Mentions
  alias TalesForge.Board.Workers.Notify
  alias TalesForge.Chat.{Message, Read, Thread, ThreadRules}
  alias TalesForge.Images
  alias TalesForge.Workflow.Repo
  alias TalesForge.WorkLog
  alias Workflow.Inbox.Event, as: InboxEvent
  alias Workflow.Inbox.Store, as: InboxStore

  @shown 100
  @context 10
  @general "general"

  @doc "True where the chat lives (production and local)."
  @spec here?() :: boolean()
  def here?, do: AppRole.here?(:board)

  @doc """
  The viewer of an author (a founder email or `bot:<id>`) with the GitHub
  `login` of the session (`TalesForge.Chat.ThreadRules.viewer/3`).
  """
  @spec viewer(String.t() | nil, String.t() | nil) :: ThreadRules.viewer()
  def viewer(author, login), do: ThreadRules.viewer(team(), author, login)

  @doc """
  Subscribes the caller to the topics that `viewer` can read. Messages
  arrive as `{:team_chat, message}`, new threads as
  `{:team_chat_thread, thread}`.
  """
  @spec subscribe(ThreadRules.viewer()) :: :ok
  def subscribe(viewer) do
    viewer
    |> ThreadRules.viewer_topics()
    |> Enum.each(&Phoenix.PubSub.subscribe(TalesForge.PubSub, &1))
  end

  defp broadcast(%Thread{} = thread, event) do
    thread
    |> ThreadRules.topics()
    |> Enum.each(&Phoenix.PubSub.broadcast(TalesForge.PubSub, &1, event))
  end

  @doc "The General thread. It holds the messages from the time before threads."
  @spec general() :: Thread.t()
  def general do
    Repo.get_by(Thread, key: @general) ||
      Repo.insert!(
        %Thread{
          key: @general,
          subject: "General",
          kind: "subject",
          members: [],
          last_message_at: DateTime.utc_now()
        },
        on_conflict: :nothing,
        conflict_target: :key
      )
      |> then(fn _ -> Repo.get_by!(Thread, key: @general) end)
  end

  @doc "The threads that `viewer` can read, newest message first."
  @spec threads(ThreadRules.viewer()) :: [Thread.t()]
  def threads(viewer) do
    _ = general()

    viewer
    |> visible_query()
    |> Repo.all()
    |> ThreadRules.visible(viewer)
  end

  # The database filter is a first cut. ThreadRules.visible/2 is the rule.
  defp visible_query({:founder, handle}) when is_binary(handle),
    do:
      from(t in Thread,
        where: is_nil(t.idea_id) and (t.kind == "subject" or ^handle in t.members)
      )

  defp visible_query(_viewer),
    do: from(t in Thread, where: is_nil(t.idea_id) and t.kind == "subject")

  @doc """
  The thread `id` when `viewer` can read it. `nil` gives the General
  thread. Returns `{:error, :not_found}` for a thread that `viewer` cannot
  read, and for an id that is not a chat thread (a card thread too).
  """
  @spec thread(ThreadRules.viewer(), Ecto.UUID.t() | nil) ::
          {:ok, Thread.t()} | {:error, :not_found}
  def thread(viewer, nil), do: viewer |> allow(general())

  def thread(viewer, id) when is_binary(id) do
    with {:ok, uuid} <- Ecto.UUID.cast(id),
         %Thread{idea_id: nil} = thread <- Repo.get(Thread, uuid) do
      allow(viewer, thread)
    else
      _ -> {:error, :not_found}
    end
  end

  def thread(_viewer, _id), do: {:error, :not_found}

  defp allow(viewer, %Thread{} = thread) do
    if ThreadRules.can_read?(thread, viewer), do: {:ok, thread}, else: {:error, :not_found}
  end

  @doc """
  Starts a subject thread with `subject`. Founders and bots can start one
  (`TalesForge.Chat.ThreadRules.subject_attrs/3`). Returns `{:ok, thread}`,
  `{:error, :forbidden}` or `{:error, changeset}`.
  """
  @spec start_subject(ThreadRules.viewer(), String.t() | nil) ::
          {:ok, Thread.t()} | {:error, :forbidden | Ecto.Changeset.t()}
  def start_subject(viewer, subject) do
    with {:ok, attrs} <- ThreadRules.subject_attrs(viewer, subject, DateTime.utc_now()),
         {:ok, thread} <- %Thread{} |> Thread.changeset(attrs) |> Repo.insert() do
      broadcast(thread, {:team_chat_thread, thread})
      {:ok, thread}
    end
  end

  @doc """
  Starts the direct thread of the founder `viewer` and the founder with
  handle `other`, or gives the one that exists. Only a founder can start
  one (`TalesForge.Chat.ThreadRules.direct_attrs/4`). Returns
  `{:ok, thread}` or `{:error, :forbidden}`.
  """
  @spec start_direct(ThreadRules.viewer(), String.t() | nil) ::
          {:ok, Thread.t()} | {:error, :forbidden}
  def start_direct(viewer, other) do
    with {:ok, attrs} <- ThreadRules.direct_attrs(team(), viewer, other, DateTime.utc_now()) do
      attrs.members
      |> find_direct()
      |> case do
        %Thread{} = thread -> allow(viewer, thread)
        nil -> insert_direct(viewer, attrs)
      end
      |> case do
        {:ok, thread} -> {:ok, thread}
        {:error, _} -> {:error, :forbidden}
      end
    end
  end

  defp find_direct(members),
    do: Repo.one(from t in Thread, where: t.kind == "direct" and t.members == ^members)

  defp insert_direct(viewer, attrs) do
    case %Thread{} |> Thread.changeset(attrs) |> Repo.insert() do
      {:ok, thread} ->
        broadcast(thread, {:team_chat_thread, thread})
        {:ok, thread}

      # Two founders started the same 1:1 at the same time.
      {:error, _changeset} ->
        attrs.members
        |> find_direct()
        |> then(&if(&1, do: allow(viewer, &1), else: {:error, :forbidden}))
    end
  end

  @doc "The threads of the card `idea_id`, newest comment first."
  @spec card_threads(Ecto.UUID.t()) :: [Thread.t()]
  def card_threads(idea_id) when is_binary(idea_id),
    do:
      Repo.all(
        from t in Thread, where: t.idea_id == ^idea_id, order_by: [desc: t.last_message_at]
      )

  @doc """
  The thread `thread_id` of the card `idea_id`. `nil` and `""` give
  `{:ok, nil}`, the General thread of the card. A thread of another card,
  a chat thread or an unknown id gives `{:error, :not_found}`.
  """
  @spec card_thread(Ecto.UUID.t(), Ecto.UUID.t() | nil) ::
          {:ok, Thread.t() | nil} | {:error, :not_found}
  def card_thread(_idea_id, thread_id) when thread_id in [nil, ""], do: {:ok, nil}

  def card_thread(idea_id, thread_id) when is_binary(thread_id) do
    with {:ok, uuid} <- Ecto.UUID.cast(thread_id),
         %Thread{} = thread <- Repo.get_by(Thread, id: uuid, idea_id: idea_id) do
      {:ok, thread}
    else
      _ -> {:error, :not_found}
    end
  end

  def card_thread(_idea_id, _thread_id), do: {:error, :not_found}

  @doc """
  Starts a thread with `subject` on the card `idea_id`, by the same rule
  as a subject thread in the chat: founders and bots can start one.
  Returns `{:ok, thread}`, `{:error, :forbidden}` or `{:error, changeset}`.
  """
  @spec start_card_thread(ThreadRules.viewer(), Ecto.UUID.t(), String.t() | nil) ::
          {:ok, Thread.t()} | {:error, :forbidden | Ecto.Changeset.t()}
  def start_card_thread(viewer, idea_id, subject) when is_binary(idea_id) do
    with {:ok, attrs} <- ThreadRules.subject_attrs(viewer, subject, DateTime.utc_now()) do
      %Thread{}
      |> Thread.changeset(Map.put(attrs, :idea_id, idea_id))
      |> Repo.insert()
    end
  end

  @doc """
  Adds a step to `multi` that sets `last_message_at` of the thread
  `thread_id` to the time of the change `key`. `nil` adds no step.
  """
  @spec touch(Multi.t(), Ecto.UUID.t() | nil, atom()) :: Multi.t()
  def touch(multi, nil, _key), do: multi

  def touch(multi, thread_id, key) do
    Multi.update_all(
      multi,
      {:touch_thread, thread_id},
      fn changes ->
        at = Map.fetch!(changes, key).inserted_at
        from(t in Thread, where: t.id == ^thread_id, update: [set: [last_message_at: ^at]])
      end,
      []
    )
  end

  @doc """
  The latest messages of the thread `thread_id` (`nil` is General), oldest
  first (at most #{@shown}), when `viewer` can read the thread. Returns
  `{:error, :not_found}` otherwise.
  """
  @spec recent(ThreadRules.viewer(), Ecto.UUID.t() | nil, pos_integer()) ::
          {:ok, [Message.t()]} | {:error, :not_found}
  def recent(viewer, thread_id, limit \\ @shown) do
    with {:ok, thread} <- thread(viewer, thread_id) do
      {:ok, thread |> messages_before(nil, limit)}
    end
  end

  @doc "The latest messages of the General thread, oldest first."
  @spec recent() :: [Message.t()]
  def recent do
    {:ok, messages} = recent(:guest, nil)
    messages
  end

  defp messages_before(%Thread{id: id}, before, limit) do
    from(m in Message,
      where: m.thread_id == ^id,
      order_by: [desc: m.inserted_at],
      limit: ^limit,
      preload: :images
    )
    |> then(&if(before, do: where(&1, [m], m.inserted_at < ^before), else: &1))
    |> Repo.all()
    |> Enum.reverse()
  end

  @doc """
  Posts `body` as `author` (a founder email or `bot:<name>`). `opts[:login]`
  is a founder author's GitHub login: it gives the founder handle, and the
  author gets no badge for their own handle (`TalesForge.Board.Mentions`).
  `opts[:thread_id]` is the thread (default: General). The author must be
  able to read the thread (`TalesForge.Chat.ThreadRules.can_post?/2`).
  `opts[:images]` is a list of image bytes (`TalesForge.Images`); with an
  image, the text can be empty.

  Returns `{:ok, message}` (images loaded), `{:error, :not_found}` for a
  thread that the author cannot read, or `{:error, changeset}`. A file that
  is not a PNG, JPEG or WebP image, or is too large, gives a changeset error
  on `:body` and stores nothing.

  In a direct thread, only the members get a mention, and no bot wakes.
  """
  @spec post(String.t(), String.t() | nil, keyword()) ::
          {:ok, Message.t()} | {:error, :not_found | Ecto.Changeset.t()}
  def post(author, body, opts \\ []) when is_binary(author) do
    body = body || ""
    images = Keyword.get(opts, :images, [])
    viewer = viewer(author, opts[:login])

    with {:ok, thread} <- thread(viewer, opts[:thread_id]) do
      case Enum.find_value(images, &image_error/1) do
        nil -> insert(thread, author, body, images, opts)
        message -> {:error, image_changeset(author, body, message)}
      end
    end
  end

  defp image_error(data) do
    case Images.validate(data) do
      :ok -> nil
      {:error, message} -> message
    end
  end

  defp image_changeset(author, body, message) do
    %Message{}
    |> Message.changeset(%{author: author, body: body}, images?: true)
    |> Ecto.Changeset.add_error(:body, message)
    |> Map.put(:action, :insert)
  end

  # One Oban insert that wakes `bot` about the stored message (with its images).
  defp add_wake(bot, multi) do
    TalesForge.Workflow.Jobs.insert(multi, {:wake, bot}, fn %{message: m, images: imgs} ->
      wake_job(bot, %{m | images: imgs})
    end)
  end

  # One Oban insert that wakes the participant `bot` about the new message.
  defp add_thread_wake(bot, multi) do
    TalesForge.Workflow.Jobs.insert(multi, {:thread_wake, bot}, fn %{message: m, images: imgs} ->
      wake_job(bot, %{m | images: imgs}, "chat.thread_message")
    end)
  end

  # The earlier posts of `thread`, for the participants (ThreadRules).
  defp thread_posts(%Thread{id: id}) do
    from(m in Message,
      where: m.thread_id == ^id,
      select: %{
        author: m.author,
        author_handle: m.author_handle,
        mentions: m.mentions,
        bots: m.bots
      }
    )
    |> Repo.all()
  end

  defp insert(%Thread{} = thread, author, body, images, opts) do
    team = team()
    author_handle = Mentions.handle_for(team, opts[:login])
    %{bots: bots, founders: mentioned} = Mentions.parse(team, body)
    founders = ThreadRules.mentions(thread, mentioned -- [author_handle])
    bot_mentions = ThreadRules.wakes(thread, bots)

    wakes =
      ThreadRules.wakes(thread, if(founder?(author), do: Mentions.wakes(team, body), else: []))

    notify =
      team
      |> ThreadRules.participants(
        thread,
        thread.created_by,
        thread_posts(thread) ++
          [
            %{
              author: author,
              author_handle: author_handle,
              mentions: founders,
              bots: bot_mentions
            }
          ]
      )
      |> ThreadRules.notify(author, author_handle, wakes)

    changeset =
      Message.changeset(
        %Message{},
        %{
          author: author,
          author_handle: author_handle,
          body: body,
          thread_id: thread.id,
          mentions: founders,
          bots: Enum.map(bot_mentions, &Atom.to_string/1)
        },
        images?: images != []
      )

    Multi.new()
    |> Multi.insert(:message, changeset)
    |> Multi.update_all(
      :thread,
      fn %{message: m} ->
        from(t in Thread,
          where: t.id == ^thread.id,
          update: [set: [last_message_at: ^m.inserted_at]]
        )
      end,
      []
    )
    |> WorkLog.add("chat", :message, & &1.author)
    |> Multi.run(:images, fn _repo, %{message: m} -> store_images(m, author, images) end)
    |> then(fn multi -> Enum.reduce(wakes, multi, &add_wake/2) end)
    |> then(fn multi -> Enum.reduce(notify.bots, multi, &add_thread_wake/2) end)
    |> InboxStore.add(team, &inbox_event(&1, author_handle, notify.founders))
    |> mark_own_read(author_handle, thread)
    |> Repo.transaction()
    |> case do
      {:ok, %{message: message, images: stored}} ->
        message = %{message | images: stored}
        broadcast(thread, {:team_chat, message})
        InboxStore.broadcast()
        {:ok, message}

      {:error, :message, changeset, _} ->
        {:error, changeset}

      {:error, :images, message, _} ->
        {:error, image_changeset(author, body, message)}
    end
  end

  # A founder who posts in a thread has read it.
  defp mark_own_read(multi, nil, _thread), do: multi

  defp mark_own_read(multi, handle, %Thread{id: id}) do
    Multi.run(multi, :own_read, fn repo, %{message: m} ->
      repo.insert(%Read{handle: handle, thread_id: id, read_at: m.inserted_at},
        on_conflict: {:replace, [:read_at]},
        conflict_target: [:handle, :thread_id]
      )
    end)
  end

  # The inbox event of a stored message (Workflow.Inbox): a message that names
  # a founder makes an item, and a message by a founder closes the chat items
  # of that founder.
  defp inbox_event(%{message: %Message{} = m}, author_handle, participants),
    do: %InboxEvent{
      type: :chat,
      source_id: m.id,
      author: m.author,
      author_handle: author_handle,
      mentions: m.mentions,
      participants: participants,
      body: m.body
    }

  defp store_images(message, author, images) do
    Enum.reduce_while(images, {:ok, []}, fn data, {:ok, acc} ->
      case Images.store({:message, message.id}, data, %{uploader: author}) do
        {:ok, image} -> {:cont, {:ok, acc ++ [image]}}
        {:error, reason} -> {:halt, {:error, reason}}
      end
    end)
  end

  @doc """
  True for a founder author (an email), false for a bot.

      iex> TalesForge.Chat.founder?("ada@example.com")
      true
      iex> TalesForge.Chat.founder?("bot:rita")
      false
  """
  @spec founder?(String.t()) :: boolean()
  def founder?("bot:" <> _), do: false
  def founder?(author), do: is_binary(author) and String.contains?(author, "@")

  @doc """
  The webhook job that wakes `bot` for `message`, with the last messages of
  the same thread as context. `event` is `"chat.mention"` (the bot is
  @mentioned) or `"chat.thread_message"` (the bot is a participant of the
  thread). The payload has the `thread_id`.
  """
  @spec wake_job(atom(), Message.t(), String.t()) :: Oban.Job.changeset()
  def wake_job(bot, %Message{} = message, event \\ "chat.mention") do
    context =
      %Thread{id: message.thread_id}
      |> messages_before(message.inserted_at, @context)

    Notify.new(%{
      "bot" => Atom.to_string(bot),
      "event" => event,
      "delivery_id" => Ecto.UUID.generate(),
      "payload" => %{
        "thread_id" => message.thread_id,
        "chat" => %{
          "thread" => thread_json(Repo.get(Thread, message.thread_id)),
          "message" => to_json(message),
          "recent" => Enum.map(context, &to_json/1),
          "reply_url" => AppRole.base_url(:production) <> "/internal/chat",
          "reply_params" => %{"thread_id" => message.thread_id}
        }
      }
    })
  end

  @doc "A message as JSON for the bots, with its image links (`images`)."
  @spec to_json(Message.t()) :: map()
  def to_json(%Message{} = m),
    do: %{
      "id" => m.id,
      "thread_id" => m.thread_id,
      "author" => m.author,
      "body" => m.body,
      "mentions" => m.mentions,
      "bots" => m.bots,
      "images" => images_json(m.images),
      "at" => m.inserted_at
    }

  @doc "A thread as JSON for the bots."
  @spec thread_json(Thread.t() | nil) :: map() | nil
  def thread_json(nil), do: nil

  def thread_json(%Thread{} = t),
    do: %{
      "id" => t.id,
      "subject" => t.subject,
      "kind" => t.kind,
      "last_message_at" => t.last_message_at
    }

  defp images_json(images) when is_list(images), do: Enum.map(images, &Images.to_json/1)
  defp images_json(_not_loaded), do: []

  @preview_words 8
  @preview_chars 60

  @typedoc """
  The latest new message on the chat button: its thread, the name of its
  author and the first words of its text.
  """
  @type latest :: %{thread_id: Ecto.UUID.t(), author: String.t(), preview: String.t()}

  @typedoc "The chat button of a founder: the count of new messages and the latest one."
  @type bar :: %{count: non_neg_integer(), latest: latest() | nil}

  @doc """
  The chat button of the founder with this GitHub `login`. `email` is the
  founder's own author email.

  A message is new when it arrived after the founder last opened its
  thread and another author wrote it. It counts when the thread is a
  direct thread of the founder, or when the founder takes part in the
  thread: the founder started it, posted in it, or was @mentioned in it
  (`TalesForge.Chat.ThreadRules.participants/4`). General uses the same
  rule. A message that also made an inbox item counts too.

  Returns the count and the latest new message (`nil` when the count is 0).
  """
  @spec bar(String.t() | nil, String.t() | nil) :: bar()
  def bar(login, email) do
    team = team()

    case Mentions.handle_for(team, login) do
      nil -> %{count: 0, latest: nil}
      handle -> bar_for(team, handle, email)
    end
  end

  defp bar_for(team, handle, email) do
    messages =
      {:founder, handle}
      |> unread_query()
      |> others(handle, email)
      |> order_by([m], desc: m.inserted_at)
      |> preload(:images)
      |> Repo.all()

    # The participant filter reads only the threads with new messages.
    joined =
      messages
      |> Enum.map(& &1.thread_id)
      |> Enum.uniq()
      |> then(&Repo.all(from t in Thread, where: t.id in ^&1))
      |> Enum.filter(&takes_part?(team, &1, handle))
      |> MapSet.new(& &1.id)

    case Enum.filter(messages, &MapSet.member?(joined, &1.thread_id)) do
      [] -> %{count: 0, latest: nil}
      [latest | _] = counted -> %{count: length(counted), latest: latest(latest)}
    end
  end

  # The messages by other authors: not the founder's handle, not their email.
  defp others(query, handle, email) do
    query
    |> where([m], is_nil(m.author_handle) or m.author_handle != ^handle)
    |> then(&if(is_binary(email), do: where(&1, [m], m.author != ^email), else: &1))
  end

  defp takes_part?(_team, %Thread{kind: "direct", members: members}, handle),
    do: handle in members

  defp takes_part?(team, %Thread{} = thread, handle) do
    team
    |> ThreadRules.participants(thread, thread.created_by, thread_posts(thread))
    |> Map.fetch!(:founders)
    |> Enum.member?(handle)
  end

  defp latest(%Message{} = m),
    do: %{thread_id: m.thread_id, author: author_name(m.author), preview: preview(m)}

  @doc """
  The first words of a message for the chat button. A message with only
  images gives "sent an image".

      iex> TalesForge.Chat.preview(%TalesForge.Chat.Message{body: "Can you  check the new card today please it is ready"})
      "Can you check the new card today please…"
      iex> TalesForge.Chat.preview(%TalesForge.Chat.Message{body: "Done"})
      "Done"
      iex> TalesForge.Chat.preview(%TalesForge.Chat.Message{body: " "})
      "sent an image"
  """
  @spec preview(Message.t()) :: String.t()
  def preview(%Message{body: body}) do
    words = (body || "") |> String.split()

    case words do
      [] -> "sent an image"
      words -> words |> Enum.take(@preview_words) |> Enum.join(" ") |> cut(length(words))
    end
  end

  defp cut(text, count) do
    cond do
      String.length(text) > @preview_chars ->
        String.slice(text, 0, @preview_chars) |> String.trim_trailing() |> Kernel.<>("…")

      count > @preview_words ->
        text <> "…"

      true ->
        text
    end
  end

  @doc """
  The name of a message author: the founder name of an email, or the bot
  name of `bot:<id>`.
  """
  @spec author_name(String.t()) :: String.t()
  def author_name("bot:" <> bot = actor) do
    team = team()

    case Workflow.Team.bot_id(team, actor) do
      nil -> String.capitalize(bot)
      id -> Workflow.Team.bot_name(team, id)
    end
  end

  def author_name(email), do: TalesForge.TeamOnline.name(team(), email)

  @doc """
  The unread count of each thread that `viewer` can read, by thread id:
  the messages by other authors since the founder last opened the thread.
  `email` is the founder's own author email. A viewer that is not a founder
  gets an empty map.
  """
  @spec unread_by_thread(ThreadRules.viewer(), String.t() | nil) :: %{
          Ecto.UUID.t() => pos_integer()
        }
  def unread_by_thread({:founder, _} = viewer, email) do
    viewer
    |> unread_query()
    |> then(&if(is_binary(email), do: where(&1, [m], m.author != ^email), else: &1))
    |> group_by([m], m.thread_id)
    |> select([m], {m.thread_id, count(m.id)})
    |> Repo.all()
    |> Map.new()
  end

  def unread_by_thread(_viewer, _email), do: %{}

  # The unread messages in the threads that the founder can read: the
  # thread ids come from ThreadRules (threads/1), not from the client.
  defp unread_query({:founder, handle} = viewer) do
    ids = viewer |> threads() |> Enum.map(& &1.id)

    from(m in Message,
      join: t in Thread,
      on: t.id == m.thread_id,
      left_join: r in Read,
      on: r.thread_id == m.thread_id and r.handle == ^handle,
      where: m.thread_id in ^ids,
      where: is_nil(r.read_at) or m.inserted_at > r.read_at
    )
  end

  @doc """
  Marks the thread `thread_id` (`nil` is General) as read for the founder
  with this GitHub `login`. A thread that the founder cannot read stays
  unchanged. The founder's own topic gets `{:team_chat_read, thread_id}`,
  so that the chat button clears in their other tabs too.
  """
  @spec mark_read(String.t() | nil, Ecto.UUID.t() | nil) :: :ok
  def mark_read(login, thread_id \\ nil) do
    with handle when is_binary(handle) <- Mentions.handle_for(team(), login),
         {:ok, thread} <- thread({:founder, handle}, thread_id) do
      Repo.insert!(%Read{handle: handle, thread_id: thread.id, read_at: DateTime.utc_now()},
        on_conflict: {:replace, [:read_at]},
        conflict_target: [:handle, :thread_id]
      )

      Phoenix.PubSub.broadcast(
        TalesForge.PubSub,
        ThreadRules.founder_topic(handle),
        {:team_chat_read, thread.id}
      )
    end

    :ok
  end

  @doc """
  The title of `thread` for `viewer`: the subject of a subject thread, or
  the name of the other founder of a direct thread.
  """
  @spec title(Thread.t(), ThreadRules.viewer()) :: String.t()
  def title(%Thread{} = thread, viewer), do: ThreadRules.title(team(), thread, viewer)

  @doc "The founders that the founder `viewer` can start a 1:1 with, as `{handle, name}`."
  @spec direct_choices(ThreadRules.viewer()) :: [{String.t(), String.t()}]
  def direct_choices(viewer), do: ThreadRules.direct_choices(team(), viewer)

  @doc "The handle of a founder's GitHub login, or nil (`TalesForge.Board.Mentions`)."
  @spec handle_for(String.t() | nil) :: String.t() | nil
  def handle_for(login), do: Mentions.handle_for(team(), login)

  @doc """
  The handle to start a message to a founder with, from their email (the
  who-is-online list knows emails, not logins): the first part of the email
  when it is a founder handle, else nil.

      iex> TalesForge.Chat.handle_for_email("lin@example.com", ~w(ada lin))
      "lin"
      iex> TalesForge.Chat.handle_for_email("orjan.gh@example.com", ~w(ada orjangh))
      nil
  """
  @spec handle_for_email(String.t() | nil, [String.t()]) :: String.t() | nil
  def handle_for_email(email, handles \\ Mentions.handles(team()))

  def handle_for_email(email, handles) when is_binary(email) do
    first = email |> String.downcase() |> String.split(["@", ".", "+"]) |> hd()
    if first in handles, do: first
  end

  def handle_for_email(_email, _handles), do: nil

  @doc "Text and mentions of a message body, to highlight the mentions."
  @spec segments(String.t()) :: [{:text | :mention, String.t()}]
  def segments(body), do: Mentions.segments(team(), body)

  @doc "The handles the message box suggests."
  @spec suggestions() :: [String.t()]
  def suggestions, do: Mentions.suggestions(team())

  @doc """
  The bots' API (`TalesForgeWeb.ChatApiController`). A bot can read and
  post only in subject threads (`TalesForge.Chat.ThreadRules`).

  - `:index` gives the latest messages of `params["thread_id"]` (default:
    General) and the threads that the bot can read.
  - `:create` posts `params["body"]` as the bot in `params["thread_id"]`
    (default: General). With `params["subject"]` and no `thread_id`, the
    bot starts a subject thread and posts in it.
  - A thread that the bot cannot read gives 404, the same as a missing
    thread. A bot never wakes another bot.
  """
  @spec api(:index | :create, atom(), map()) :: {pos_integer(), map()}
  def api(:index, bot, params) do
    viewer = viewer("bot:#{bot}", nil)

    with {:ok, thread} <- thread(viewer, params["thread_id"]),
         {:ok, messages} <- recent(viewer, thread.id, 50) do
      {200,
       %{
         "thread" => thread_json(thread),
         "threads" => viewer |> threads() |> Enum.map(&thread_json/1),
         "messages" => Enum.map(messages, &to_json/1)
       }}
    else
      {:error, :not_found} -> {404, %{"error" => "not_found"}}
    end
  end

  def api(:create, bot, params) do
    author = "bot:#{bot}"

    with {:ok, thread_id} <- api_thread(viewer(author, nil), params),
         {:ok, m} <- post(author, to_string(params["body"] || ""), thread_id: thread_id) do
      {201, to_json(m)}
    else
      {:error, :not_found} -> {404, %{"error" => "not_found"}}
      {:error, :forbidden} -> {404, %{"error" => "not_found"}}
      {:error, cs} -> {422, %{"errors" => Ecto.Changeset.traverse_errors(cs, &elem(&1, 0))}}
    end
  end

  # The thread of a bot post: thread_id, or a new subject thread.
  defp api_thread(_viewer, %{"thread_id" => id}) when is_binary(id) and id != "", do: {:ok, id}

  defp api_thread(viewer, %{"subject" => subject}) when is_binary(subject) do
    with {:ok, thread} <- start_subject(viewer, subject), do: {:ok, thread.id}
  end

  defp api_thread(_viewer, _params), do: {:ok, nil}

  defp team, do: Workflow.Team.Source.team()
end
