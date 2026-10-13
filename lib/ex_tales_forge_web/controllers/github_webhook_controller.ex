defmodule TalesForgeWeb.GitHubWebhookController do
  @moduledoc """
  `POST /webhooks/github`: GitHub's repository webhook
  (`docs/github-webhooks.md`).

  - 404 while `GITHUB_WEBHOOK_SECRET` is unset (the endpoint is off).
  - 401 when `X-Hub-Signature-256` is not the HMAC-SHA256 of the raw body
    with the secret (`TalesForge.GitEvents.Signature`).
  - 202 for an event the app reads: it is broadcast on `"github"`
    (`TalesForge.GitEvents`).
  - 204 for any other event (also `ping`).
  """

  use TalesForgeWeb, :controller

  alias TalesForge.GitEvents
  alias TalesForge.GitEvents.Mapper
  alias TalesForge.GitEvents.Signature

  @doc "Checks, maps and broadcasts one delivery."
  @spec create(Plug.Conn.t(), map()) :: Plug.Conn.t()
  def create(conn, _params) do
    raw = conn.assigns[:raw_body] || ""
    header = conn |> get_req_header("x-hub-signature-256") |> List.first()

    case GitEvents.secret() do
      nil ->
        send_resp(conn, 404, "")

      secret ->
        if Signature.valid?(secret, raw, header),
          do: dispatch(conn),
          else: send_resp(conn, 401, "")
    end
  end

  defp dispatch(conn) do
    name = conn |> get_req_header("x-github-event") |> List.first()

    case Mapper.map(name, conn.body_params) do
      {:ok, event} ->
        GitEvents.broadcast(event)
        send_resp(conn, 202, "")

      :ignore ->
        send_resp(conn, 204, "")
    end
  end
end
