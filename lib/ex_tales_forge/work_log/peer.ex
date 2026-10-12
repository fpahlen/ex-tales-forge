defmodule TalesForge.WorkLog.Peer do
  @moduledoc """
  Production's copy of the playtest work log events, for
  `TalesForge.WorkLog`. The same pattern as `TalesForge.Online.Peer` and
  `TalesForge.Costs.Peer`.

  On production with `COSTS_PEER_TOKEN` set, it asks playtest's
  `GET /internal/work-log/events?since=<time>` every 60 s (5 s timeout, no
  retries, no redirects). `since` is the newest stored playtest event. It
  stores the new events with the app `playtest`. Rows that exist already
  stay as they are, so a repeated answer adds nothing. On playtest and
  locally it never polls.
  """

  use GenServer

  alias TalesForge.AppRole
  alias TalesForge.WorkLog

  @path "/internal/work-log/events"
  @interval_ms 60_000
  @timeout_ms 5_000
  @first_since ~U[2026-01-01 00:00:00Z]

  @doc false
  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(opts \\ []), do: GenServer.start_link(__MODULE__, opts, name: __MODULE__)

  @doc "The URL production reads: playtest's base URL plus `#{@path}`."
  @spec url() :: String.t()
  def url, do: String.trim_trailing(AppRole.base_url(:playtest), "/") <> @path

  @doc """
  Fetches the new playtest events once and stores them. Returns
  `{:ok, count}` with the count of new rows, or `{:error, reason}` when the
  token is unset or playtest does not answer well. Never raises.
  """
  @spec sync() :: {:ok, non_neg_integer()} | {:error, term()}
  def sync do
    case AppRole.peer_token() do
      nil -> {:error, :not_configured}
      token -> token |> request(WorkLog.latest_at("playtest") || @first_since) |> store()
    end
  end

  defp store({:ok, list}), do: {:ok, WorkLog.put_peer_events(list, "playtest")}
  defp store(error), do: error

  defp request(token, since) do
    case Req.get(
           [
             url: url(),
             params: [since: DateTime.to_iso8601(since)],
             auth: {:bearer, token},
             receive_timeout: @timeout_ms,
             connect_options: [timeout: @timeout_ms],
             retry: false,
             redirect: false
           ] ++ Application.get_env(:ex_tales_forge, :work_log_peer_req_options, [])
         ) do
      {:ok, %Req.Response{status: 200, body: %{"events" => list}}} when is_list(list) ->
        {:ok, list}

      {:ok, %Req.Response{status: status}} ->
        {:error, {:http_status, status}}

      {:error, _} ->
        {:error, :unreachable}
    end
  rescue
    _ -> {:error, :unreachable}
  end

  @impl true
  def init(_opts) do
    if polls?(), do: send(self(), :poll)
    {:ok, nil}
  end

  @impl true
  def handle_info(:poll, state) do
    _ = sync()
    Process.send_after(self(), :poll, @interval_ms)
    {:noreply, state}
  end

  def handle_info(_msg, state), do: {:noreply, state}

  defp polls?, do: AppRole.role() == :production and AppRole.peer_token() != nil
end
