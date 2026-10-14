defmodule TalesForge.Board.Workers.Notify do
  @moduledoc """
  Wakes a bot about a board event: a signed JSON POST to that bot's webhook
  (`BOARD_WEBHOOK_URL_<BOT>`, key `BOARD_WEBHOOK_KEY_<BOT>`; config
  `:board_bots`, `TalesForge.BoardApi.bot_config/1`).

  Request: `Content-Type: application/json`, `Authorization: Bearer <key>`,
  `X-Board-Event`, `X-Board-Delivery` (a UUID, the same on every retry, so the
  bot can drop duplicates), `X-Board-Timestamp` (Unix seconds) and
  `X-Board-Signature: sha256=<hex HMAC-SHA256 of "<timestamp>.<body>" with the
  key>`. Body: `event`, `delivery_id`, `bot`, `idea` (id, title, column, url),
  `transition` (from, to, actor) and, for a mention, `comment`. A
  `chat.thread_message` wake also has `thread_id`.

  A `schedule.run` wake (`run_job/3` with a scheduled run) has no card: the
  body has `job` (id, name, limit_min), `run` (id, started_at, deadline_at,
  UTC) and `finish` (the path for the report,
  `POST /internal/board/runs/:id/finish`).

  A `run.failed` wake (`run_job/3` with an atom event and a run map) has no
  card: the body has `transition` (actor `bot:board`) and `run` (repo,
  workflow, branch, sha, url, actor).

  Any 2xx ends it. A pooled connection the bot already closed (`:closed`) is
  retried once at once in the same attempt. Otherwise Oban retries up to 10
  times, fast at first so a short outage of the bot costs seconds, not half an
  hour: 10 s, 30 s, 1 min, 2 min, 2 min, then doubling up to 4 h (`backoff/1`).
  The job is idempotent: the delivery id is in the args, so a retry or a job
  rescued after a deploy (Oban.Plugins.Lifeline) sends the same id. A bot without a URL is skipped (the job is cancelled).
  Queue `:board`.
  """

  use Oban.Worker, queue: :board, max_attempts: 10

  alias TalesForge.Board
  alias TalesForge.Board.Idea
  alias TalesForge.BoardApi

  @doc "The job that wakes `bot` about `event` on `idea`."
  @spec job(BoardApi.bot(), atom(), Idea.t(), map()) :: Oban.Job.changeset()
  def job(bot, event, %Idea{} = idea, extra) do
    new(%{
      "bot" => Atom.to_string(bot),
      "event" => event_name(event),
      "delivery_id" => Ecto.UUID.generate(),
      "payload" =>
        %{
          "idea" => %{
            "id" => idea.id,
            "title" => idea.title,
            "column" => extra[:to] || idea.column,
            "url" => Board.url(idea)
          },
          "transition" => Map.take(stringify(extra), ~w(from to actor)),
          "comment" =>
            if(extra[:body],
              do: %{
                "author" => extra[:author],
                "body" => extra[:body],
                "thread_id" => extra[:thread_id]
              }
            )
        }
        |> Map.merge(pr_fields(extra))
        |> Map.merge(thread_fields(event, extra))
    })
  end

  @doc """
  The card-less `schedule.run` job that wakes `bot` for the run `run` of the
  scheduled job `job` (`TalesForge.Board.Schedule.start_bot_run/3`).
  """
  @spec run_job(BoardApi.bot(), Workflow.Team.job(), TalesForge.Board.ScheduledRun.t()) ::
          Oban.Job.changeset()
  def run_job(bot, job, %TalesForge.Board.ScheduledRun{} = run) when is_map(job) do
    new(%{
      "bot" => Atom.to_string(bot),
      "event" => "schedule.run",
      "delivery_id" => Ecto.UUID.generate(),
      "payload" => %{
        "job" => %{"id" => job.id, "name" => job.name, "limit_min" => job.limit_min},
        "run" => %{
          "id" => run.id,
          "started_at" => DateTime.to_iso8601(run.started_at),
          "deadline_at" => DateTime.to_iso8601(run.deadline_at)
        },
        "finish" => %{"method" => "POST", "path" => "/internal/board/runs/#{run.id}/finish"}
      }
    })
  end

  @doc """
  The job that wakes `bot` about a GitHub Actions run that names no card
  (`run.failed`: a failed run on main). Body: `event`, `delivery_id`, `bot`,
  `transition` (actor `bot:board`) and `run` (repo, workflow, branch, sha, url,
  actor).
  """
  @spec run_job(BoardApi.bot(), atom(), map()) :: Oban.Job.changeset()
  def run_job(bot, event, run) when is_atom(event) and is_map(run) do
    new(%{
      "bot" => Atom.to_string(bot),
      "event" => event_name(event),
      "delivery_id" => Ecto.UUID.generate(),
      "payload" => %{"transition" => %{"actor" => "bot:board"}, "run" => run}
    })
  end

  # pr.approved / pr.changes_requested: the PR, the founder and the comment.
  defp pr_fields(%{pr: pr} = extra),
    do: %{"pr" => pr, "approver" => extra[:approver], "comment" => extra[:comment]}

  defp pr_fields(%{question: q}), do: %{"question" => q}
  defp pr_fields(_extra), do: %{}

  # chat.thread_message: the card thread of the comment (nil is the General
  # thread of the card).
  defp thread_fields(:chat_thread_message, extra), do: %{"thread_id" => extra[:thread_id]}
  defp thread_fields(_event, _extra), do: %{}

  @doc """
  The event's wire name.

      iex> TalesForge.Board.Workers.Notify.event_name(:idea_to_refining)
      "idea.to_refining"
  """
  @spec event_name(atom()) :: String.t()
  def event_name(event) do
    case Atom.to_string(event) do
      "idea_" <> rest -> "idea." <> rest
      other -> String.replace(other, "_", ".", global: false)
    end
  end

  @doc "The signature header value for `body` sent at `timestamp` with `key`."
  @spec signature(String.t(), String.t(), String.t()) :: String.t()
  def signature(key, timestamp, body),
    do:
      "sha256=" <>
        Base.encode16(:crypto.mac(:hmac, :sha256, key, timestamp <> "." <> body), case: :lower)

  @impl Oban.Worker
  @spec backoff(Oban.Job.t()) :: pos_integer()
  def backoff(%Oban.Job{attempt: attempt}) when attempt <= 5,
    do: Enum.at([10, 30, 60, 120, 120], attempt - 1)

  def backoff(%Oban.Job{attempt: attempt}), do: min(120 * Integer.pow(2, attempt - 5), 4 * 3600)

  # Well inside Lifeline's rescue_after and the deploy's grace period.
  @impl Oban.Worker
  def timeout(_job), do: :timer.seconds(30)

  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"bot" => bot} = args}) do
    config = BoardApi.bot_config(String.to_existing_atom(bot))

    case {config[:webhook_url], config[:webhook_key]} do
      {url, key} when is_binary(url) and is_binary(key) -> post(url, key, args)
      _ -> {:cancel, "no webhook URL and key for #{bot}"}
    end
  end

  defp post(url, key, args) do
    body =
      Jason.encode!(
        Map.merge(args["payload"], %{
          "event" => args["event"],
          "delivery_id" => args["delivery_id"],
          "bot" => args["bot"]
        })
      )

    ts = Integer.to_string(System.system_time(:second))

    headers = [
      {"content-type", "application/json"},
      {"authorization", "Bearer " <> key},
      {"x-board-event", args["event"]},
      {"x-board-delivery", args["delivery_id"]},
      {"x-board-timestamp", ts},
      {"x-board-signature", signature(key, ts, body)}
    ]

    opts =
      Keyword.merge(
        [
          body: body,
          headers: headers,
          retry: false,
          receive_timeout: 10_000,
          connect_options: [timeout: 5_000]
        ],
        Application.get_env(:ex_tales_forge, :board_req_options, [])
      )

    case post_once_more_if_closed(url, opts) do
      {:ok, %{status: status}} when status in 200..299 -> :ok
      {:ok, %{status: status}} -> {:error, "webhook answered #{status}"}
      {:error, reason} -> {:error, reason}
    end
  end

  # The bot closed an idle pooled connection: send again on a fresh one now
  # instead of waiting for Oban's first retry.
  defp post_once_more_if_closed(url, opts) do
    case Req.post(url, opts) do
      {:error, %Req.TransportError{reason: :closed}} -> Req.post(url, opts)
      other -> other
    end
  end

  defp stringify(map), do: Map.new(map, fn {k, v} -> {to_string(k), v} end)
end
