defmodule TalesForgeWeb.WorkLogPeerController do
  @moduledoc """
  `GET /internal/work-log/events?since=<ISO 8601 time>`, served by the
  playtest app only. It gives the playtest work log events after `since`,
  oldest first, at most 1000, as JSON `{"events": [...]}`. Production
  stores them (`TalesForge.WorkLog.Peer`).

  Guarded like `/internal/online` by the shared `COSTS_PEER_TOKEN` as a
  bearer token (`TalesForgeWeb.PeerToken`). On production or local, or with
  the token unset: 404. Missing or wrong token: 401. A bad `since`: 400.
  """

  use TalesForgeWeb, :controller

  alias TalesForge.AppRole
  alias TalesForge.WorkLog
  alias TalesForgeWeb.PeerToken

  @doc "Playtest's events after `since`, for a caller with the shared token."
  @spec show(Plug.Conn.t(), map()) :: Plug.Conn.t()
  def show(conn, params) do
    with :playtest <- AppRole.role(),
         expected when is_binary(expected) <- AppRole.peer_token() do
      if PeerToken.authorized?(conn, expected),
        do: answer(conn, params),
        else: PeerToken.unauthorized(conn)
    else
      _ -> PeerToken.not_found(conn)
    end
  end

  defp answer(conn, params) do
    case DateTime.from_iso8601(to_string(params["since"])) do
      {:ok, since, _} ->
        conn
        |> put_resp_header("cache-control", "no-store")
        |> json(%{events: since |> WorkLog.local_events_after() |> Enum.map(&WorkLog.to_json/1)})

      _ ->
        conn |> put_status(400) |> json(%{error: "since must be an ISO 8601 time."})
    end
  end
end
