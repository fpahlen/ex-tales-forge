defmodule TalesForge.Chat do
  @moduledoc """
  The team chat (board card "Team chat with mentions", decision 2026-10-10):
  one shared room for the founders and the bots. It lives on production only,
  like the board (`TalesForge.AppRole` area `:board`).

  - Messages are in `team_chat_messages` and arrive live over PubSub
    (`subscribe/0`). History stays (how long we keep it is a deferred
    question on the card).
  - Mentions use the board's one parser, `TalesForge.Board.Mentions`:
    `@<founder handle>`, `@founders`, `@<bot id>` and `@devops` (all bots of
    the team config, `Workflow.Team`).
  - A founder mention gives that founder an unread badge on the chat button
    (`unread/1`, by GitHub login) until they open the chat (`mark_read/1`). No email or push
    (the founder's answer on the card).
  - A bot mention **by a founder** wakes the bot through the board's webhook
    outbox (`TalesForge.Board.Workers.Notify`, event `chat.mention`), in the
    same transaction as the message. A bot that mentions a bot wakes nobody,
    to keep bot costs under control (the founder's answer on the card).
  - A message that names a founder with inbox rules makes an item in that
    founder's inbox (`Workflow.Inbox`), in the same transaction. For that
    founder the inbox replaces the unread badge: `unread/1` gives 0. A
    message by that founder closes the chat items of that founder.
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
  alias TalesForge.Chat.{Message, Read}
  alias TalesForge.Images
  alias TalesForge.Repo
  alias TalesForge.WorkLog
  alias Workflow.Inbox.Event, as: InboxEvent
  alias Workflow.Inbox.Store, as: InboxStore

  @topic "team_chat"
  @shown 100
  @context 10

  @doc "True where the chat lives (production and local)."
  @spec here?() :: boolean()
  def here?, do: AppRole.here?(:board)

  @doc "Subscribes the caller to `{:team_chat, message}`."
  @spec subscribe() :: :ok | {:error, term()}
  def subscribe, do: Phoenix.PubSub.subscribe(TalesForge.PubSub, @topic)

  @doc "The latest messages, oldest first (at most #{@shown})."
  @spec recent(pos_integer()) :: [Message.t()]
  def recent(limit \\ @shown) do
    from(m in Message, order_by: [desc: m.inserted_at], limit: ^limit, preload: :images)
    |> Repo.all()
    |> Enum.reverse()
  end

  @doc """
  Posts `body` as `author` (a founder email or `bot:<name>`). `opts[:login]`
  is a founder author's GitHub login, so the author gets no badge for their
  own handle (handles come from GitHub logins, `TalesForge.Board.Mentions`).
  `opts[:images]` is a list of image bytes (`TalesForge.Images`); with an
  image, the text can be empty. Returns `{:ok, message}` (images loaded) or
  `{:error, changeset}`. A file that is not a PNG, JPEG or WebP image, or is too
  large, gives a changeset error on `:body` and stores nothing.
  """
  @spec post(String.t(), String.t() | nil, keyword()) ::
          {:ok, Message.t()} | {:error, Ecto.Changeset.t()}
  def post(author, body, opts \\ []) when is_binary(author) do
    body = body || ""
    images = Keyword.get(opts, :images, [])

    case Enum.find_value(images, &image_error/1) do
      nil -> insert(author, body, images, opts)
      message -> {:error, image_changeset(author, body, message)}
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
    Oban.insert(multi, {:wake, bot}, fn %{message: m, images: imgs} ->
      wake_job(bot, %{m | images: imgs})
    end)
  end

  defp insert(author, body, images, opts) do
    team = team()
    %{bots: bots, founders: mentioned} = Mentions.parse(team, body)
    founders = mentioned -- [Mentions.handle_for(team, opts[:login])]
    wakes = if founder?(author), do: Mentions.wakes(team, body), else: []

    changeset =
      Message.changeset(
        %Message{},
        %{
          author: author,
          body: body,
          mentions: founders,
          bots: Enum.map(bots, &Atom.to_string/1)
        },
        images?: images != []
      )

    Multi.new()
    |> Multi.insert(:message, changeset)
    |> WorkLog.add("chat", :message, & &1.author)
    |> Multi.run(:images, fn _repo, %{message: m} -> store_images(m, author, images) end)
    |> then(fn multi -> Enum.reduce(wakes, multi, &add_wake/2) end)
    |> InboxStore.add(team, &inbox_event(&1, Mentions.handle_for(team, opts[:login])))
    |> Repo.transaction()
    |> case do
      {:ok, %{message: message, images: stored}} ->
        message = %{message | images: stored}
        Phoenix.PubSub.broadcast(TalesForge.PubSub, @topic, {:team_chat, message})
        InboxStore.broadcast()
        {:ok, message}

      {:error, :message, changeset, _} ->
        {:error, changeset}

      {:error, :images, message, _} ->
        {:error, image_changeset(author, body, message)}
    end
  end

  # The inbox event of a stored message (Workflow.Inbox): a message that names
  # a founder makes an item, and a message by a founder closes the chat items
  # of that founder.
  defp inbox_event(%{message: %Message{} = m}, author_handle),
    do: %InboxEvent{
      type: :chat,
      source_id: m.id,
      author: m.author,
      author_handle: author_handle,
      mentions: m.mentions,
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

  @doc "The webhook job that wakes `bot` for `message` (with the last messages as context)."
  @spec wake_job(atom(), Message.t()) :: Oban.Job.changeset()
  def wake_job(bot, %Message{} = message) do
    context =
      from(m in Message,
        where: m.inserted_at < ^message.inserted_at,
        order_by: [desc: m.inserted_at],
        limit: @context,
        preload: :images
      )
      |> Repo.all()
      |> Enum.reverse()

    Notify.new(%{
      "bot" => Atom.to_string(bot),
      "event" => "chat.mention",
      "delivery_id" => Ecto.UUID.generate(),
      "payload" => %{
        "chat" => %{
          "message" => to_json(message),
          "recent" => Enum.map(context, &to_json/1),
          "reply_url" => AppRole.base_url(:production) <> "/internal/chat"
        }
      }
    })
  end

  @doc "A message as JSON for the bots, with its image links (`images`)."
  @spec to_json(Message.t()) :: map()
  def to_json(%Message{} = m),
    do: %{
      "id" => m.id,
      "author" => m.author,
      "body" => m.body,
      "mentions" => m.mentions,
      "bots" => m.bots,
      "images" => images_json(m.images),
      "at" => m.inserted_at
    }

  defp images_json(images) when is_list(images), do: Enum.map(images, &Images.to_json/1)
  defp images_json(_not_loaded), do: []

  @doc "How many messages mention the founder with this GitHub `login` since they last opened the chat."
  @spec unread(String.t() | nil) :: non_neg_integer()
  def unread(login) do
    team = team()

    case Mentions.handle_for(team, login) do
      nil ->
        0

      handle ->
        if Workflow.Inbox.has_inbox?(team, handle), do: 0, else: unread_count(handle)
    end
  end

  defp unread_count(handle) do
    read_at = Repo.one(from r in Read, where: r.handle == ^handle, select: r.read_at)

    from(m in Message, where: ^handle in m.mentions)
    |> then(&if(read_at, do: where(&1, [m], m.inserted_at > ^read_at), else: &1))
    |> Repo.aggregate(:count)
  end

  @doc "Marks the chat as read for the founder with this GitHub `login` (they opened it)."
  @spec mark_read(String.t() | nil) :: :ok
  def mark_read(login) do
    case Mentions.handle_for(team(), login) do
      nil ->
        :ok

      handle ->
        Repo.insert!(%Read{handle: handle, read_at: DateTime.utc_now()},
          on_conflict: {:replace, [:read_at]},
          conflict_target: :handle
        )

        :ok
    end
  end

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
  The bots' API (`TalesForgeWeb.ChatApiController`): `:index` gives the
  latest messages, `:create` posts `params["body"]` as the bot. A bot never
  wakes another bot.
  """
  @spec api(:index | :create, atom(), map()) :: {pos_integer(), map()}
  def api(:index, _bot, _params), do: {200, %{"messages" => Enum.map(recent(50), &to_json/1)}}

  def api(:create, bot, params) do
    case post("bot:#{bot}", to_string(params["body"] || "")) do
      {:ok, m} -> {201, to_json(m)}
      {:error, cs} -> {422, %{"errors" => Ecto.Changeset.traverse_errors(cs, &elem(&1, 0))}}
    end
  end

  defp team, do: Workflow.Team.Source.team()
end
