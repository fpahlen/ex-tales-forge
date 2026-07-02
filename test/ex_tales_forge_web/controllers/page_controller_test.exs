defmodule TalesForgeWeb.PageControllerTest do
  use TalesForgeWeb.ConnCase

  test "GET / renders the home live view", %{conn: conn} do
    conn = get(conn, ~p"/")
    assert html_response(conn, 200) =~ "Your adventures await"
  end
end
