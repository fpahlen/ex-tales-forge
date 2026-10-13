defmodule TalesForgeWeb.TeamConfigRenderTest do
  @moduledoc """
  The board and the team pages show the same data before and after the move of
  the team names into the team config (board card "Workflow split 2/5: Team
  config"). The fixtures under `test/fixtures/team_render/` hold the visible
  text and the labels of each page, rendered on `main` before the change.

  Set `UPDATE_TEAM_RENDER=1` to write the fixtures again. Do this only for a
  change that must change the page text.
  """
  use TalesForgeWeb.ConnCase, async: false

  import Phoenix.LiveViewTest

  alias TalesForge.Board

  @dir "test/fixtures/team_render"
  @founder "founder@example.com"

  setup %{conn: conn} do
    {:ok, a} = Board.create_idea(@founder, %{"title" => "Golden idea in Ideas"})
    {:ok, _} = Board.vote(a, @founder, 1)

    {:ok, r} = Board.create_idea(@founder, %{"title" => "Golden card in Refining"})
    {:ok, r} = Board.vote(r, @founder, 1)
    {:ok, r} = Board.move(r, {:founder, @founder}, "refining")

    {:ok, _} =
      Board.add_comment(r, "bot:case", "Refinement started. @bobby please read.")

    {:ok, c} = Board.create_idea(@founder, %{"title" => "Golden card in Founder check"})
    {:ok, c} = Board.vote(c, @founder, 1)
    {:ok, c} = Board.move(c, {:founder, @founder}, "refining")

    {:ok, c} =
      Board.refine(c, %{
        "details" => "Details of the golden card.",
        "verdict" => "feasible",
        "rough_cost" => "S",
        "open_questions" => ["Is this the golden question?"]
      })

    {:ok, c} = Board.move(c, {:bot, :case}, "check")

    {:ok, conn: log_in_admin(conn), cards: [r, c]}
  end

  test "an open card on the board shows the same text and labels as before",
       %{conn: conn, cards: cards} do
    {:ok, view, _html} = live(conn, "/team")

    got =
      Enum.map_join(cards, fn card ->
        view |> element("#tile-#{card.id} button[aria-haspopup]") |> render_click()
        view |> element("#board-modal") |> render() |> visible()
      end)

    check("card", got)
  end

  for {name, path} <- [
        {"team", "/team"},
        {"presentation", "/team/presentation"}
      ] do
    @name name
    @path path

    test "#{path} shows the same text and labels as before", %{conn: conn} do
      {:ok, view, _html} = live(conn, @path)
      check(@name, view |> render() |> visible())
    end
  end

  defp check(name, got) do
    file = Path.join(@dir, name <> ".txt")
    if System.get_env("UPDATE_TEAM_RENDER") == "1", do: File.write!(file, got)
    assert_same(File.read!(file), got)
  end

  # The visible text, then the alt, title, aria-label and placeholder values.
  # Times, ids and numbers that change on each run are masked.
  defp visible(html) do
    doc = LazyHTML.from_document(html)
    body = doc |> LazyHTML.query("body") |> then(&if(Enum.empty?(&1), do: doc, else: &1))

    text = LazyHTML.text(body)

    attrs =
      for a <- ~w(alt title aria-label placeholder),
          el <- LazyHTML.query(body, "[#{a}]"),
          v <- LazyHTML.attribute(el, a),
          do: a <> "=" <> v

    (lines(text) ++ attrs)
    |> Enum.map(&mask/1)
    |> Enum.join("\n")
    |> Kernel.<>("\n")
  end

  defp lines(text) do
    text
    |> String.split(~r/\n/)
    |> Enum.map(&(&1 |> String.replace(~r/\s+/u, " ") |> String.trim()))
    |> Enum.reject(&(&1 == ""))
  end

  defp mask(line) do
    line
    |> String.replace(~r/[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}/, "<uuid>")
    |> String.replace(~r/\d{1,2}:\d{2}/, "<time>")
    |> String.replace(~r/\b\d+ (s|sec|min|h|hour|hours|minutes|seconds|d|days?) ago\b/, "<ago>")
    |> String.replace(~r/just now|\bnow\b/, "<ago>")
    |> String.replace(~r/\b\d+ days? (remaining|left)\b/, "<days> remaining")
    |> String.replace(~r/\b\d{4}-\d{2}-\d{2}\b/, "<date>")
    |> String.replace(
      ~r/\b\d{1,2} (Jan|Feb|Mar|Apr|May|Jun|Jul|Aug|Sep|Oct|Nov|Dec)[a-z]*( \d{4})?\b/,
      "<date>"
    )
  end

  # The words are compared, not the line breaks: a change in how the HEEx
  # source wraps a sentence is not a change on the page. The online counts
  # come from presence, which other tests also use, so they are masked here.
  defp assert_same(want, got) do
    {want, got} = {words(want), words(got)}

    if want != got do
      diff =
        want
        |> List.myers_difference(got)
        |> Enum.reject(&match?({:eq, _}, &1))

      flunk("The page text changed:\n" <> inspect(diff, pretty: true, limit: :infinity))
    end
  end

  defp words(text) do
    text
    |> String.replace(~r/(Founders|Bots): \d+/, "\\1: <n>")
    |> String.split()
  end
end
