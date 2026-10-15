defmodule TalesForgeWeb.WebAppControllerTest do
  use TalesForgeWeb.ConnCase, async: false

  setup do
    on_exit(fn -> Application.delete_env(:ex_tales_forge, :app_name) end)
    :ok
  end

  test "the manifest, icons and service worker are served logged out" do
    conn = get(build_conn(), "/manifest.webmanifest")
    assert conn.status == 200
    assert [type | _] = get_resp_header(conn, "content-type")
    assert type =~ "application/manifest+json"

    manifest = Jason.decode!(conn.resp_body)
    assert manifest["name"] == "Tales Forge"
    assert manifest["start_url"] == "/"
    assert manifest["display"] == "standalone"
    assert Enum.any?(manifest["icons"], &(&1["purpose"] == "maskable"))

    for path <-
          ~w(/sw.js /app/icon-192.png /app/icon-512.png /app/icon-maskable-512.png /app/apple-touch-icon.png) do
      assert get(build_conn(), path).status == 200, path
    end
  end

  test "playtest names the app Tales Forge Playtest" do
    Application.put_env(:ex_tales_forge, :app_name, "tales-forge-playtest")
    conn = get(build_conn(), "/manifest.webmanifest")
    assert Jason.decode!(conn.resp_body)["name"] == "Tales Forge Playtest"
  end

  test "the login page carries the app head tags" do
    html = build_conn() |> get("/admin/login") |> html_response(200)
    assert html =~ ~s(rel="manifest" href="/manifest.webmanifest")
    assert html =~ "apple-mobile-web-app-title"
  end
end
