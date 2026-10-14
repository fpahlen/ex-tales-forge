defmodule TalesForgeWeb.TeamAppTest do
  use TalesForgeWeb.ConnCase, async: false

  import Phoenix.LiveViewTest

  doctest TalesForgeWeb.Layouts

  @team Workflow.Team.Source.team()
  @owner Enum.find(@team.founders, &(&1.inbox != []))
  @owner_email "owner@example.com"

  setup do
    vapid = Application.get_env(:web_push_ex, :vapid)
    {public, private} = :crypto.generate_key(:ecdh, :prime256v1)

    Application.put_env(:web_push_ex, :vapid,
      public_key: Base.url_encode64(public, padding: false),
      private_key: Base.url_encode64(private, padding: false)
    )

    on_exit(fn ->
      if vapid,
        do: Application.put_env(:web_push_ex, :vapid, vapid),
        else: Application.delete_env(:web_push_ex, :vapid)
    end)

    %{key: Base.url_encode64(public, padding: false)}
  end

  defp owner(conn), do: log_in_admin(conn, @owner_email, login: @owner.github)

  test "the team page links the manifest and has the push hook with the key", %{
    conn: conn,
    key: key
  } do
    html = conn |> owner() |> get(~p"/team") |> html_response(200)

    assert html =~ ~s(rel="manifest" href="/team-app/manifest.webmanifest")
    assert html =~ ~s(rel="apple-touch-icon")
    assert html =~ ~s(phx-hook="TeamPush")
    assert html =~ ~s(data-key="#{key}")
  end

  test "other pages have no manifest link" do
    html = build_conn() |> get(~p"/admin/login") |> html_response(200)
    refute html =~ "manifest.webmanifest"
  end

  test "the hook stores the subscription of the founder", %{conn: conn} do
    {:ok, view, _html} = conn |> owner() |> live(~p"/team")
    {client_public, _} = :crypto.generate_key(:ecdh, :prime256v1)

    render_hook(view, "push:subscribe", %{
      "endpoint" => "https://push.example.com/send/live",
      "keys" => %{
        "p256dh" => Base.url_encode64(client_public, padding: false),
        "auth" => Base.url_encode64(:crypto.strong_rand_bytes(16), padding: false)
      }
    })

    assert [%{endpoint: "https://push.example.com/send/live"}] =
             Workflow.Push.subscriptions(@owner.handle)
  end

  test "the manifest names the app and starts at /team" do
    manifest = Jason.decode!(File.read!("priv/static/team-app/manifest.webmanifest"))

    assert manifest["name"] == "Tales Forge team"
    assert manifest["start_url"] == "/team"
    assert manifest["display"] == "standalone"

    assert Enum.any?(
             manifest["icons"],
             &(&1["purpose"] == "maskable" and &1["sizes"] == "512x512")
           )
  end

  test "the service worker handles install and push only, and caches nothing" do
    sw = File.read!("priv/static/team-sw.js")

    assert sw =~ ~s(addEventListener("install")
    assert sw =~ ~s(addEventListener("push")
    refute sw =~ ~s(addEventListener("fetch")
    refute sw =~ "caches."
  end
end
