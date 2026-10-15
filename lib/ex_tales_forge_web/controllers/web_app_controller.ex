defmodule TalesForgeWeb.WebAppController do
  @moduledoc """
  `GET /manifest.webmanifest`: the web app manifest that makes Tales Forge
  installable (a PWA). Public on purpose, like `/health`: a browser fetches it
  without the session cookie, and the rest of the site needs a signed-in team
  member. The icons (`/app/*`) and the service worker (`/sw.js`) are static
  files served by the endpoint before the router.

  The name is a runtime value: "Tales Forge Playtest" on the playtest app
  (`TalesForge.AppRole`), "Tales Forge" elsewhere, so the two installs can be
  told apart.
  """

  use TalesForgeWeb, :controller

  alias TalesForge.AppRole

  @theme "#1b1713"

  @doc "The installed app's name for this app."
  @spec app_name() :: String.t()
  def app_name,
    do: if(AppRole.playtest?(AppRole.app_name()), do: "Tales Forge Playtest", else: "Tales Forge")

  @doc "The site's dark theme colour, used for the manifest and `theme-color`."
  @spec theme_color() :: String.t()
  def theme_color, do: @theme

  @doc "The manifest as JSON (`application/manifest+json`)."
  @spec manifest(Plug.Conn.t(), map()) :: Plug.Conn.t()
  def manifest(conn, _params) do
    name = app_name()

    body = %{
      id: "/",
      name: name,
      short_name: name,
      start_url: "/",
      scope: "/",
      display: "standalone",
      background_color: @theme,
      theme_color: @theme,
      icons: [
        %{src: "/app/icon-192.png", sizes: "192x192", type: "image/png", purpose: "any"},
        %{src: "/app/icon-512.png", sizes: "512x512", type: "image/png", purpose: "any"},
        %{
          src: "/app/icon-maskable-512.png",
          sizes: "512x512",
          type: "image/png",
          purpose: "maskable"
        }
      ]
    }

    conn
    |> put_resp_header("cache-control", "public, max-age=3600")
    |> put_resp_content_type("application/manifest+json")
    |> send_resp(200, Jason.encode!(body))
  end
end
