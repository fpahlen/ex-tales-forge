defmodule TalesForgeWeb.QaLoginController do
  @moduledoc """
  Gentry's QA sign-in at `/team/qa-login` (`TalesForge.QaLogin`).

  - `GET` shows a form with one password field for the token.
  - `POST` compares the token (timing safe). A correct token starts a
    read-only browser session as "Gentry (QA)" and goes to `/team`. A wrong or
    missing token gets 401 and the form again, with no hint about the token.
  - While GENTRY_QA_TOKEN is unset, both answer 404.

  The token travels in the POST body only (never in the URL), with the usual
  CSRF check of the `:public_browser` pipeline.
  """

  use TalesForgeWeb, :controller

  require Logger

  alias TalesForge.AdminAuth
  alias TalesForge.QaLogin

  plug :require_enabled

  @doc "The token form."
  @spec new(Plug.Conn.t(), map()) :: Plug.Conn.t()
  def new(conn, _params), do: form(conn, 200, nil)

  @doc "Checks the token and starts the QA session."
  @spec create(Plug.Conn.t(), map()) :: Plug.Conn.t()
  def create(conn, params) do
    if QaLogin.token_valid?(params["token"]) do
      Logger.info("QA sign-in: Gentry (QA) signed in")

      conn
      |> AdminAuth.clear_session()
      |> QaLogin.put_session()
      |> put_flash(:info, "Signed in as Gentry (QA).")
      |> redirect(to: ~p"/team")
    else
      Logger.warning("QA sign-in: token refused")
      form(conn, 401, "That token is not correct.")
    end
  end

  defp form(conn, status, error) do
    conn
    |> put_resp_header("cache-control", "no-store")
    |> put_status(status)
    |> put_view(html: TalesForgeWeb.QaLoginHTML)
    |> render(:new, error: error, token: get_csrf_token())
  end

  defp require_enabled(conn, _opts) do
    if QaLogin.enabled?() do
      conn
    else
      conn |> send_resp(404, "Not found") |> halt()
    end
  end
end
