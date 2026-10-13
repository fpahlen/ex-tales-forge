defmodule TalesForge.Board.Workers.MentionSweep do
  @moduledoc """
  Finds unanswered bot mentions (bot cost cut, decision 2026-10-13 "Bot work
  in Elixir"; it replaces Case's sweep every 15 minutes). Every 15 minutes
  (`Oban.Plugins.Cron`, config), production only (`TalesForge.AppRole`).

  A mention is unanswered when a founder mentions a bot in a board comment or
  in the team chat, 15 minutes or more ago and less than 24 hours ago, and
  that bot (`bot:<name>`) wrote nothing after it in the same place (the same
  card, or the chat).

  When the count is above 0, one `TalesForge.Board.Workers.Notify` job wakes
  Case with the list (event `mention.unanswered`). When the count is 0, no bot
  wakes. The same list wakes Case only once in 24 hours (Oban `unique` on the
  mention ids).

  `unanswered/3` is the pure decision over plain `%Mention{}` and `%Reply{}`
  structs. `run/1` reads the rows and adds the job.
  """
  use Oban.Worker, queue: :board, max_attempts: 3, unique: [period: 300]

  import Ecto.Query

  alias TalesForge.AppRole
  alias TalesForge.Board.{Comment, Mentions}
  alias TalesForge.Board.Workers.Notify
  alias TalesForge.Chat
  alias TalesForge.Chat.Message
  alias TalesForge.Repo

  @wait_s 15 * 60
  @window_s 24 * 3600

  defmodule Mention do
    @moduledoc "A founder's mention of one bot in one place (a card id or `\"chat\"`)."
    @enforce_keys [:id, :place, :bot, :author, :at]
    defstruct @enforce_keys

    @type t :: %__MODULE__{
            id: String.t(),
            place: String.t(),
            bot: atom(),
            author: String.t(),
            at: DateTime.t()
          }
  end

  defmodule Reply do
    @moduledoc "A comment or chat message by `author` in a place."
    @enforce_keys [:place, :author, :at]
    defstruct @enforce_keys
    @type t :: %__MODULE__{place: String.t(), author: String.t(), at: DateTime.t()}
  end

  @doc """
  The mentions that have no answer: by a founder, #{div(@wait_s, 60)} minutes
  old or older, and with no later reply by that bot in the same place.

      iex> alias TalesForge.Board.Workers.MentionSweep.{Mention, Reply}
      iex> m = %Mention{id: "c1", place: "card1", bot: :bobby, author: "ada@x.se",
      ...>   at: ~U[2026-10-13 07:00:00Z]}
      iex> now = ~U[2026-10-13 08:00:00Z]
      iex> TalesForge.Board.Workers.MentionSweep.unanswered([m], [], now) |> length()
      1
      iex> reply = %Reply{place: "card1", author: "bot:bobby", at: ~U[2026-10-13 07:05:00Z]}
      iex> TalesForge.Board.Workers.MentionSweep.unanswered([m], [reply], now)
      []
  """
  @spec unanswered([Mention.t()], [Reply.t()], DateTime.t()) :: [Mention.t()]
  def unanswered(mentions, replies, now) do
    Enum.filter(mentions, fn m ->
      Chat.founder?(m.author) and DateTime.diff(now, m.at) >= @wait_s and
        not Enum.any?(replies, &answers?(&1, m))
    end)
  end

  defp answers?(%Reply{} = r, %Mention{} = m),
    do: r.place == m.place and r.author == "bot:#{m.bot}" and DateTime.compare(r.at, m.at) == :gt

  @doc "The wake job for a list of unanswered mentions, or nil for an empty list."
  @spec job([Mention.t()]) :: Oban.Job.changeset() | nil
  def job([]), do: nil

  def job(mentions) do
    ids = mentions |> Enum.map(& &1.id) |> Enum.sort()

    Notify.new(
      %{
        "bot" => "case",
        "event" => "mention.unanswered",
        "delivery_id" => Ecto.UUID.generate(),
        "ids" => ids,
        "payload" => %{
          "mentions" =>
            Enum.map(mentions, fn m ->
              %{
                "id" => m.id,
                "place" => m.place,
                "bot" => Atom.to_string(m.bot),
                "author" => m.author,
                "at" => m.at
              }
            end)
        }
      },
      unique: [period: @window_s, fields: [:worker, :args], keys: [:event, :ids]]
    )
  end

  @impl Oban.Worker
  def perform(%Oban.Job{}) do
    if AppRole.role() == :production, do: run(DateTime.utc_now())
    :ok
  end

  @doc "Adds the wake job when some mentions have no answer. Returns the count."
  @spec run(DateTime.t()) :: {:ok, non_neg_integer()}
  def run(now) do
    since = DateTime.add(now, -@window_s)
    {mentions, replies} = read(since)
    found = unanswered(mentions, replies, now)

    case job(found) do
      nil -> :ok
      job -> {:ok, _} = Oban.insert(job)
    end

    {:ok, length(found)}
  end

  defp read(since) do
    comments =
      Repo.all(
        from(c in Comment,
          where: c.inserted_at >= ^since,
          select: %{id: c.id, place: c.idea_id, author: c.author, body: c.body, at: c.inserted_at}
        )
      )

    messages =
      Repo.all(
        from(m in Message,
          where: m.inserted_at >= ^since,
          select: %{id: m.id, place: "chat", author: m.author, body: m.body, at: m.inserted_at}
        )
      )

    rows = comments ++ messages

    mentions =
      for row <- rows,
          bot <- Mentions.parse(row.body || "", []).bots,
          do: %Mention{
            id: "#{row.id}:#{bot}",
            place: row.place,
            bot: bot,
            author: row.author,
            at: row.at
          }

    replies = for row <- rows, do: %Reply{place: row.place, author: row.author, at: row.at}
    {mentions, replies}
  end
end
