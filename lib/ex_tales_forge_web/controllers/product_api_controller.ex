defmodule TalesForgeWeb.ProductApiController do
  @moduledoc """
  The product-app API that Workflow reads (`TalesForge.ProductApi`,
  `Workflow.ProductApp.Http`). No other data.

  - `GET /internal/product/costs`: the AI spend of each day and the intent
    latency, last 7 days.
  - `GET /internal/product/online`: the founders online.
  - `GET /internal/product/running-commits`: the commit that each app runs.

  The secret `PRODUCT_APP_API_TOKEN` is the bearer token (config
  `:product_api`). Token unset: 404 (the API is off). Missing or wrong token:
  401. No route calls an LLM.
  """

  use TalesForgeWeb, :controller

  alias TalesForge.ProductApi
  alias TalesForgeWeb.PeerToken

  @doc "The costs of the last 7 days."
  @spec costs(Plug.Conn.t(), map()) :: Plug.Conn.t()
  def costs(conn, _params), do: guarded(conn, fn -> ProductApi.costs(DateTime.utc_now()) end)

  @doc "The founders online."
  @spec online(Plug.Conn.t(), map()) :: Plug.Conn.t()
  def online(conn, _params), do: guarded(conn, &ProductApi.online/0)

  @doc "The commit that each app runs."
  @spec running_commits(Plug.Conn.t(), map()) :: Plug.Conn.t()
  def running_commits(conn, _params), do: guarded(conn, &ProductApi.running_commits/0)

  defp guarded(conn, body) do
    case ProductApi.token() do
      nil ->
        PeerToken.not_found(conn)

      expected ->
        if PeerToken.authorized?(conn, expected) do
          conn |> put_resp_header("cache-control", "no-store") |> json(body.())
        else
          PeerToken.unauthorized(conn)
        end
    end
  end
end
