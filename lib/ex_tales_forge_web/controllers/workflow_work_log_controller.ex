defmodule TalesForgeWeb.WorkflowWorkLogController do
  @moduledoc """
  `POST /internal/workflow/work-log/turns`: Workflow receives one work-log
  turn event from the product app (`TalesForge.WorkLog.receive_turn/1`).

  The body is JSON: `founder`, `ref` (the turn id), `at` (ISO 8601) and
  `app`. The secret `WORKFLOW_API_TOKEN` is the bearer token (config
  `:workflow_api`). Token unset: 404 (the route is off). Missing or wrong
  token: 401. A bad body: 422. The same event two times stores one row, so
  the sender can retry.
  """

  use TalesForgeWeb, :controller

  alias TalesForge.WorkLog
  alias TalesForgeWeb.PeerToken

  @doc "Stores one work-log turn event."
  @spec create(Plug.Conn.t(), map()) :: Plug.Conn.t()
  def create(conn, params) do
    case WorkLog.api_token() do
      nil ->
        PeerToken.not_found(conn)

      expected ->
        if PeerToken.authorized?(conn, expected),
          do: store(conn, params),
          else: PeerToken.unauthorized(conn)
    end
  end

  defp store(conn, params) do
    case WorkLog.receive_turn(params) do
      {:ok, result} ->
        json(conn, %{result: Atom.to_string(result)})

      {:error, :invalid} ->
        conn |> put_status(422) |> json(%{error: "invalid turn event"})
    end
  end
end
