defmodule TalesForgeWeb.Plugs.AdminAuth do
  @moduledoc false

  @behaviour Plug

  def init(opts), do: opts

  def call(conn, _opts) do
    config = Application.get_env(:ex_tales_forge, :admin_auth, [])

    if config[:enabled] == false do
      conn
    else
      username = Keyword.get(config, :username, "admin")
      password = Keyword.get(config, :password, "admin")
      Plug.BasicAuth.basic_auth(conn, username: username, password: password)
    end
  end
end
