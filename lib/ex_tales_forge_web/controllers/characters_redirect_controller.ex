defmodule TalesForgeWeb.CharactersRedirectController do
  @moduledoc """
  Keeps a session's old NPC admin URLs working (NPC cleanup PR 6):
  `/admin/play/sessions/:id/npcs` and everything below it redirect (302) to
  the same place under `.../characters`, with the query string.
  """

  use TalesForgeWeb, :controller

  @doc "Redirects an old `/npcs` path to its `/characters` path."
  @spec show(Plug.Conn.t(), map()) :: Plug.Conn.t()
  def show(conn, _params) do
    # The first "/npcs" is the session's: the id before it is a UUID.
    path = String.replace(conn.request_path, "/npcs", "/characters", global: false)

    redirect(conn,
      to: if(conn.query_string == "", do: path, else: path <> "?" <> conn.query_string)
    )
  end
end
