defmodule TalesForgeWeb.WorkLogApiController do
  @moduledoc """
  The bots' API for the manual work log entries (`TalesForge.WorkLog.Entry`):

  - `GET /internal/work-log/entries` lists the manual entries, oldest first.
    Optional `from` and `to` (ISO 8601 dates) limit the days.
  - `POST /internal/work-log/entries` adds one entry with `founder` (an
    email), `date`, `hours` and `reason`. `added_by` is the bot
    (`bot:<name>`). An entry with the same founder, date and reason is already
    there: the API keeps it and answers `"skipped"`, so a bot can send the
    same import again. A new entry answers `"ok"` (status 201).

  A bot uses its board bearer token (`BOARD_BOT_TOKEN_<BOT>`,
  `TalesForge.BoardApi.bot_for_token/1`). Missing or unknown token: 401.
  A bad body: 422.
  """

  use TalesForgeWeb, :controller

  alias TalesForge.BoardApi
  alias TalesForge.WorkLog
  alias TalesForgeWeb.PeerToken

  @doc "Lists the manual entries for an authorised bot."
  @spec index(Plug.Conn.t(), map()) :: Plug.Conn.t()
  def index(conn, params) do
    with_bot(conn, fn conn, _bot ->
      case {date(params["from"], ~D[2000-01-01]), date(params["to"], ~D[2100-01-01])} do
        {{:ok, from}, {:ok, to}} ->
          entries = from |> WorkLog.entries(to) |> Enum.map(&entry_json/1)
          json(conn, %{entries: entries})

        _ ->
          conn |> put_status(422) |> json(%{error: "from and to must be ISO 8601 dates"})
      end
    end)
  end

  @doc "Adds one manual entry as an authorised bot, or skips a duplicate."
  @spec create(Plug.Conn.t(), map()) :: Plug.Conn.t()
  def create(conn, params) do
    with_bot(conn, fn conn, bot ->
      attrs = Map.take(params, ~w(founder date hours reason))

      case WorkLog.add_bot_entry("bot:#{bot}", attrs) do
        {:ok, :skipped, entry} ->
          json(conn, %{result: "skipped", entry: entry_json(entry)})

        {:ok, entry} ->
          conn |> put_status(201) |> json(%{result: "ok", entry: entry_json(entry)})

        {:error, %Ecto.Changeset{} = cs} ->
          conn |> put_status(422) |> json(%{errors: errors(cs)})
      end
    end)
  end

  defp with_bot(conn, fun) do
    case conn |> bearer() |> BoardApi.bot_for_token() do
      nil ->
        PeerToken.unauthorized(conn)

      bot ->
        :ok = Workflow.BotCalls.seen(bot)
        conn |> put_resp_header("cache-control", "no-store") |> fun.(bot)
    end
  end

  defp date(nil, default), do: {:ok, default}
  defp date(value, _default) when is_binary(value), do: Date.from_iso8601(value)
  defp date(_value, _default), do: :error

  defp entry_json(e) do
    %{
      id: e.id,
      founder: e.founder,
      date: Date.to_iso8601(e.date),
      hours: e.minutes / 60,
      reason: e.reason,
      added_by: e.added_by
    }
  end

  defp errors(cs) do
    Ecto.Changeset.traverse_errors(cs, fn {msg, opts} ->
      Enum.reduce(opts, msg, fn {k, v}, acc -> String.replace(acc, "%{#{k}}", to_string(v)) end)
    end)
  end

  defp bearer(conn) do
    case get_req_header(conn, "authorization") do
      ["Bearer " <> token] -> token
      _ -> nil
    end
  end
end
