defmodule TalesForge.Board.SimilarTest do
  use TalesForge.DataCase, async: true

  alias TalesForge.Board
  alias TalesForge.Board.Similar

  doctest Similar

  defp idea(title, body \\ ""),
    do: elem(Board.create_idea("bo@example.com", %{"title" => title, "body" => body}), 1)

  test "no cards: no AI call, the title comes from the first line" do
    llm = fn _, _, _ -> flunk("no AI call without cards") end

    assert {:ok, %{title: "Fishing at the mill", matches: []}} =
             Similar.check("Fishing at the mill\nWith rods.", candidates: [], llm: llm)
  end

  test "an empty idea is an error" do
    assert {:error, :empty} = Similar.check("  ", candidates: [])
  end

  test "maps refs to cards, marks Done cards, drops unknown refs and keeps three" do
    open = idea("Fishing", "Players fish at the mill.")
    done = %{idea("Fishing rods") | column: "done"}
    others = for n <- 1..3, do: idea("Other #{n}")
    cards = [open, done | others]
    parent = self()

    llm = fn system, prompt, _opts ->
      send(parent, {:prompt, system, prompt})

      {:ok,
       %{
         "title" => "Fish at the mill",
         "matches" => [
           %{"ref" => "c2", "reason" => "Same feature."},
           %{"ref" => "c1", "reason" => "Close variant."},
           %{"ref" => "c99", "reason" => "Unknown."},
           %{"ref" => "c1", "reason" => "Twice."},
           %{"ref" => "c3", "reason" => "x"},
           %{"ref" => "c4", "reason" => "y"}
         ]
       }}
    end

    assert {:ok, %{title: "Fish at the mill", matches: matches}} =
             Similar.check("Let players fish", candidates: cards, llm: llm)

    assert [d, o, _] = matches
    assert d.idea.id == done.id and d.done and d.reason == "Same feature."
    assert o.idea.id == open.id and not o.done

    assert_received {:prompt, _system, prompt}
    assert prompt =~ "Let players fish"
    assert prompt =~ "c1 [ideas] Fishing — Players fish at the mill."
    assert prompt =~ "c2 [done] Fishing rods"
  end

  test "an empty AI title falls back to the text" do
    llm = fn _, _, _ -> {:ok, %{"title" => " ", "matches" => []}} end
    assert {:ok, %{title: "Boats"}} = Similar.check("Boats", candidates: [idea("Xyz")], llm: llm)
  end

  test "an AI error is returned" do
    llm = fn _, _, _ -> {:error, :timeout} end
    assert {:error, :timeout} = Similar.check("Boats", candidates: [idea("Xyz")], llm: llm)
  end

  test "candidates: every card but the archived ones" do
    a = idea("Kept")
    {:ok, p} = Board.move(a, {:founder, "bo@example.com"}, "parked")
    b = idea("Gone")
    {:ok, _} = Board.archive(b, "bo@example.com", "spam")

    ids = Enum.map(Similar.candidates(), & &1.id)
    assert p.id in ids
    refute b.id in ids
  end

  test "fallback_title cuts a long line at a word" do
    title = Similar.fallback_title(String.duplicate("word ", 40))
    assert String.length(title) <= 121
    assert String.ends_with?(title, "word…")
  end

  test "card_attrs keeps the full text as the body unless it is only the title" do
    assert %{"title" => "Boats", "body" => ""} = Similar.card_attrs("Boats", "Boats")

    assert %{"title" => "Boats", "body" => "Boats\nOn the lake."} =
             Similar.card_attrs("Boats", "Boats\nOn the lake.")
  end
end
