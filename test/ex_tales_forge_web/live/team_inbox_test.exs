defmodule TalesForgeWeb.TeamInboxTest do
  use TalesForgeWeb.ConnCase, async: false

  import Phoenix.LiveViewTest

  alias TalesForge.Board
  alias TalesForge.Chat
  alias Workflow.Inbox.Store

  doctest TalesForgeWeb.TeamInbox

  @team Workflow.Team.Source.team()
  @owner Enum.find(@team.founders, &(&1.inbox != []))
  @other Enum.find(@team.founders, &(&1.inbox == []))
  @owner_email "owner@example.com"
  @other_email "other@example.com"

  setup do
    Application.put_env(:ex_tales_forge, :inbox_undo_ms, 30)
    on_exit(fn -> Application.delete_env(:ex_tales_forge, :inbox_undo_ms) end)
  end

  # Waits until the action of the undo toast applies (the test undo time is
  # short, and a slow machine can need more time).
  defp settle(view, tries \\ 60) do
    _ = render(view)

    cond do
      not has_element?(view, "#inbox-toast") -> :ok
      tries == 0 -> flunk("the undo toast stays")
      true -> Process.sleep(50) && settle(view, tries - 1)
    end
  end

  defp owner(conn), do: log_in_admin(conn, @owner_email, login: @owner.github)

  defp mention(text \\ "look") do
    {:ok, idea} = Board.create_idea(@other_email, %{"title" => "Inbox card"})
    {:ok, _} = Board.add_comment(idea, @other_email, "@#{@owner.handle} #{text}")
    idea
  end

  test "a founder with rules sees 'Inbox zero' under New idea, and no pings", %{conn: conn} do
    {:ok, view, html} = live(owner(conn), "/team")
    assert has_element?(view, "#inbox #inbox-zero", "Inbox zero")
    refute has_element?(view, "#board-pings")
    assert has_element?(view, "#stat-inbox")
    # The panel follows the New idea box.
    assert :binary.match(html, ~s(id="board-chat")) < :binary.match(html, ~s(id="inbox"))
  end

  test "a founder with no rules sees no inbox and keeps the pings", %{conn: conn} do
    {:ok, idea} = Board.create_idea(@owner_email, %{"title" => "Ping card"})
    {:ok, _} = Board.add_comment(idea, @owner_email, "@#{@other.handle} look")

    {:ok, view, _} = live(log_in_admin(conn, @other_email, login: @other.github), "/team")
    refute has_element?(view, "#inbox")
    assert has_element?(view, "#board-pings")
    assert has_element?(view, "#stat-pings")
  end

  test "an item shows the count, the chip and the answer field", %{conn: conn} do
    idea = mention("what do you think?")
    {:ok, view, _} = live(owner(conn), "/team")

    assert has_element?(view, ~s(#inbox [data-role="inbox-count"]), "1")
    assert has_element?(view, "#inbox-chip summary", "Card: Inbox card")
    assert has_element?(view, ~s(#inbox-chip-body a[href="/team#idea-#{idea.id}"]))
    assert has_element?(view, "#inbox-answer-text[data-inbox-answer]")
  end

  test "Enter in the answer sends a card comment after the undo time and closes the item",
       %{conn: conn} do
    idea = mention()
    {:ok, view, _} = live(owner(conn), "/team")

    view |> form("#inbox-answer", %{answer: "Yes, build it."}) |> render_submit()
    settle(view)

    assert [%{body: "Yes, build it.", author: @owner_email}] =
             Board.get_idea(idea.id).comments |> Enum.filter(&(&1.author == @owner_email))

    assert Store.open(@owner.handle) == []
    assert has_element?(view, "#inbox-zero")
  end

  test "undo keeps the item open", %{conn: conn} do
    Application.put_env(:ex_tales_forge, :inbox_undo_ms, 5_000)
    mention()
    {:ok, view, _} = live(owner(conn), "/team")

    view |> element("#inbox") |> render_hook("key", %{"key" => "e"})
    assert has_element?(view, "#inbox-toast", "Marked done.")
    view |> element("#inbox-undo") |> render_click()

    refute has_element?(view, "#inbox-toast")
    assert [%{state: "new"}] = Store.open(@owner.handle)
  end

  test "keys: d discards, s skips to the end, j and k move", %{conn: conn} do
    mention("one")
    {:ok, _} = Chat.post(@other_email, "@#{@owner.handle} two")
    {:ok, view, _} = live(owner(conn), "/team")
    [first, second] = Store.open(@owner.handle)

    assert has_element?(view, ~s(#inbox-item[data-item-id="#{first.id}"]))
    view |> element("#inbox") |> render_hook("key", %{"key" => "j"})
    assert has_element?(view, ~s(#inbox-item[data-item-id="#{second.id}"]))
    view |> element("#inbox") |> render_hook("key", %{"key" => "k"})
    assert has_element?(view, ~s(#inbox-item[data-item-id="#{first.id}"]))

    view |> element("#inbox") |> render_hook("key", %{"key" => "s"})
    settle(view)
    assert Enum.map(Store.open(@owner.handle), & &1.id) == [second.id, first.id]

    view |> element("#inbox") |> render_hook("key", %{"key" => "d"})
    settle(view)
    assert %{state: "discarded"} = Store.get(second.id)
  end

  test "a swipe left skips and a swipe right marks the item done", %{conn: conn} do
    mention()
    {:ok, view, _} = live(owner(conn), "/team")
    [item] = Store.open(@owner.handle)

    view |> element("#inbox") |> render_hook("swipe", %{"dir" => "left"})
    settle(view)
    assert [%{id: id, state: "new"}] = Store.open(@owner.handle)
    assert id == item.id

    view |> element("#inbox") |> render_hook("swipe", %{"dir" => "right"})
    settle(view)
    assert %{state: "done"} = Store.get(item.id)
  end

  test "a new item shows live", %{conn: conn} do
    {:ok, view, _} = live(owner(conn), "/team")
    assert has_element?(view, "#inbox-zero")
    {:ok, _} = Chat.post(@other_email, "@#{@owner.handle} live")
    _ = render(view)
    assert has_element?(view, "#inbox-chip summary", "Team chat")
  end

  test "Enter in a Founder check item answers the question on the card", %{conn: conn} do
    {:ok, idea} = Board.create_idea(@other_email, %{"title" => "Check card"})

    {:ok, idea} = Board.vote(idea, @other_email, 1)
    {:ok, idea} = Board.move(idea, {:founder, @other_email}, "refining")

    {:ok, idea} =
      Board.refine(idea, %{
        "open_questions" => ["How big?"],
        "rough_cost" => "S",
        "verdict" => "feasible"
      })

    {:ok, _} = Board.move(idea, {:bot, Workflow.Team.bot(@team, :refiner)}, "check")

    {:ok, view, _} = live(owner(conn), "/team")
    assert has_element?(view, "#inbox-chip summary", "Founder check: Check card")
    assert has_element?(view, "#inbox-item-body", "How big?")

    view |> form("#inbox-answer", %{answer: "Small, one PR."}) |> render_submit()
    settle(view)

    assert [{"How big?", %{answer: "Small, one PR."}}] =
             Board.questions(Board.get_idea!(idea.id))

    assert Store.open(@owner.handle) == []
  end
end
