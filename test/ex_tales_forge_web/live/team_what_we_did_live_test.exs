defmodule TalesForgeWeb.TeamWhatWeDidLiveTest do
  use TalesForgeWeb.ConnCase, async: false

  import Phoenix.LiveViewTest
  import TalesForge.PrFeedFixtures

  alias TalesForge.PrFeed
  alias TalesForge.PrFeed.WhatWeDid

  setup %{conn: conn} do
    isolate_cache()
    WhatWeDid.clear_cache()

    on_exit(fn ->
      WhatWeDid.clear_cache()
      Application.delete_env(:ex_tales_forge, :what_we_did_llm)
    end)

    {:ok, conn: log_in_admin(conn)}
  end

  defp publish_merged do
    repo = Workflow.Team.Source.team().repo_url
    now = DateTime.utc_now()

    merged = [
      %{
        number: 41,
        title: "Add the inn",
        url: "#{repo}/pull/41",
        merged_at: DateTime.add(now, -60)
      },
      %{
        number: 40,
        title: "Fix the door",
        url: "#{repo}/pull/40",
        merged_at: DateTime.add(now, -120)
      }
    ]

    PrFeed.publish(snapshot([], merged: merged))
  end

  defp panel(conn) do
    {:ok, view, _html} = live(conn, ~p"/team")
    child = find_live_child(view, "team-what-we-did")
    _ = render_async(child)
    {view, child}
  end

  test "the panel shows the model's bullets with links to the pull requests", %{conn: conn} do
    Application.put_env(:ex_tales_forge, :what_we_did_llm, fn _system, _user, _opts ->
      {:ok,
       %{"bullets" => [%{"text" => "The inn is new and its door works.", "prs" => [41, 40]}]}}
    end)

    publish_merged()
    {view, child} = panel(conn)

    assert has_element?(view, "#done-title", "What have we done")
    assert has_element?(child, "#what-we-did[data-source='ai'][data-count='2']")
    assert has_element?(child, "#what-we-did-bullets li", "The inn is new and its door works.")
    assert has_element?(child, "a[data-pr='41'][href$='/pull/41']", "#41")
    assert has_element?(child, "a[data-pr='40']", "#40")
  end

  test "a failed call shows the plain titles", %{conn: conn} do
    Application.put_env(:ex_tales_forge, :what_we_did_llm, fn _, _, _ -> {:error, :timeout} end)
    publish_merged()
    {_view, child} = panel(conn)

    assert has_element?(child, "#what-we-did[data-source='titles']")
    assert has_element?(child, "#what-we-did-bullets li", "Add the inn")
    assert has_element?(child, "#what-we-did-titles")
  end

  test "no merged pull requests: a short note", %{conn: conn} do
    PrFeed.publish(snapshot([]))
    {_view, child} = panel(conn)
    assert has_element?(child, "#what-we-did-empty")
  end
end
