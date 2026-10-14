defmodule Workflow.ProductApp.Http do
  @moduledoc """
  The HTTP adapter of `Workflow.ProductApp`. It calls the product app's
  `GET /internal/product/*` routes (`TalesForgeWeb.ProductApiController`).

  - Base URL: config `:ex_tales_forge, Workflow.ProductApp, base_url:`.
  - Token: the secret `PRODUCT_APP_API_TOKEN` as a bearer token (config
    `:ex_tales_forge, :product_api, token:`).
  - 2 s timeout, no retries, no redirects. A missing token or base URL, a
    slow product app or a bad answer gives `:error`.
  """

  @behaviour Workflow.ProductApp

  @timeout_ms 2_000

  @impl Workflow.ProductApp
  def costs(%DateTime{} = now), do: get("/internal/product/costs", now: DateTime.to_iso8601(now))

  @impl Workflow.ProductApp
  def online, do: get("/internal/product/online", [])

  @impl Workflow.ProductApp
  def running_commits, do: get("/internal/product/running-commits", [])

  defp get(path, params) do
    with url when is_binary(url) <- base_url(),
         token when is_binary(token) <- token() do
      request(String.trim_trailing(url, "/") <> path, params, token)
    else
      _ -> :error
    end
  end

  defp request(url, params, token) do
    case Req.get(
           [
             url: url,
             params: params,
             auth: {:bearer, token},
             receive_timeout: @timeout_ms,
             connect_options: [timeout: @timeout_ms],
             retry: false,
             redirect: false
           ] ++ Application.get_env(:ex_tales_forge, :product_app_req_options, [])
         ) do
      {:ok, %Req.Response{status: 200, body: %{} = body}} -> {:ok, body}
      _other -> :error
    end
  rescue
    _ -> :error
  end

  defp base_url, do: Application.get_env(:ex_tales_forge, Workflow.ProductApp, [])[:base_url]

  defp token do
    case Application.get_env(:ex_tales_forge, :product_api, [])[:token] do
      token when is_binary(token) and token != "" -> token
      _ -> nil
    end
  end
end
