defmodule TalesForgeWeb.PageController do
  use TalesForgeWeb, :controller

  def home(conn, _params) do
    render(conn, :home)
  end
end
