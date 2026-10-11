defmodule TalesForge.Board.HistoryTest do
  use ExUnit.Case, async: true

  alias TalesForge.Board.History

  doctest History

  @t0 ~U[2026-10-11 11:00:00Z]

  defp at(min), do: DateTime.add(@t0, min * 60)

  defp tr(min, attrs),
    do:
      Map.merge(
        %{from: "building", to: "building", actor: "fredrik@x", note: nil, inserted_at: at(min)},
        attrs
      )

  defp idea(transitions, extra \\ %{}) do
    Map.merge(
      %{
        transitions: transitions,
        comments: [],
        links: [%{kind: "pr", label: "PR #171", url: "https://github.com/o/r/pull/171"}],
        pr_number: 171,
        pr_url: "https://github.com/o/r/pull/171"
      },
      extra
    )
  end

  defp one(attrs), do: idea([tr(0, attrs)]) |> History.entries() |> hd()

  test "a new card" do
    assert %{kind: :added, text: "added this card to Ideas"} = one(%{from: nil, to: "ideas"})

    assert %{text: "added this card from the decision queue"} =
             one(%{from: nil, to: "ideas", actor: "import", note: "From the decision queue: x"})

    assert %{text: "made this card for a PR"} =
             one(%{from: nil, actor: "bot:bobby", note: "Bobby made this card for a PR."})
  end

  test "a move, without the move note" do
    e = one(%{from: "ideas", to: "refining", note: "Secret move note"})
    assert e.kind == :moved
    assert e.text == "moved Ideas → Refining"
    refute inspect(e) =~ "Secret"
  end

  test "Case's move to Founder check is the refinement" do
    assert %{kind: :refined, actor: "bot:case", text: "wrote the refinement" <> _} =
             one(%{from: "refining", to: "check", actor: "bot:case"})
  end

  test "the board moves the card to Done with the release" do
    assert %{text: "moved to Done (release v150)"} =
             one(%{
               to: "done",
               actor: "bot:board",
               note:
                 "PR #171 is in the prod release ae5df15 (v150). The board moved the card to Done."
             })

    assert %{text: "moved to Done (release ae5df15)"} =
             one(%{
               to: "done",
               actor: "bot:board",
               note: "PR #171 is in the prod release ae5df15. The board moved the card to Done."
             })
  end

  test "answers, deferrals and reopened questions, without the text" do
    e = one(%{note: "Answered: Which sea? Answer: The north one"})
    assert e.text == "answered a question"
    refute inspect(e) =~ "north"
    assert %{text: "deferred a question"} = one(%{note: "Deferred: Which sea?"})
    assert %{text: "opened a question again"} = one(%{note: "Open again (not deferred): Q"})
  end

  test "consecutive answers by the same person are one line" do
    entries =
      History.entries(
        idea([
          tr(0, %{note: "Answered: A Answer: x"}),
          tr(1, %{note: "Answered: B Answer: y"}),
          tr(2, %{note: "Answered: C Answer: z", actor: "hakan@x"}),
          tr(3, %{note: "Deferred: D"}),
          tr(4, %{note: "Deferred: E"})
        ])
      )

    assert Enum.map(entries, &{&1.actor, &1.text}) == [
             {"fredrik@x", "answered 2 questions"},
             {"hakan@x", "answered a question"},
             {"fredrik@x", "deferred 2 questions"}
           ]

    assert hd(entries).at == at(1)
  end

  test "the decision log entry: a link to the commit, no text" do
    url = "https://github.com/o/docs/commit/abc"

    i =
      idea([tr(0, %{actor: "board", note: "Decision log entry written: abc"})], %{
        links: [%{kind: "decision", label: "Decision log", url: url}]
      })

    assert [%{kind: :decision, text: "Decision logged", link: {"(commit)", ^url}}] =
             History.entries(i)
  end

  test "PR events link to the PR" do
    link = {"PR #171", "https://github.com/o/r/pull/171"}

    assert %{kind: :pr_linked, text: "linked", link: ^link} =
             one(%{
               actor: "bot:bobby",
               note: "PR #171 (abc1234) waits for a founder's OK: Players see X"
             })

    assert %{kind: :pr_waiting, text: "asked for a founder's OK on", link: ^link} =
             one(%{actor: "bot:board", note: "PR #171 (abc1234) waits for a founder's OK."})

    assert %{kind: :pr_relinked, link: ^link, tail: "again"} =
             one(%{actor: "bot:bobby", note: "PR #171 (abc1234) linked again; approval kept."})

    assert %{kind: :new_commit, text: "added a new commit to", link: ^link} =
             one(%{actor: "bot:bobby", note: "New commit abc1234 on PR #171."})

    assert %{
             kind: :new_commit_after_approval,
             link: ^link,
             tail: "after approval. The approval stays."
           } =
             one(%{actor: "bot:bobby", note: "New commit abc1234 after approval; approval kept."})

    e = one(%{note: "Approved PR #171 (abc1234): Ship it now"})
    assert %{kind: :pr_approved, text: "approved", link: ^link} = e
    refute inspect(e) =~ "Ship it"

    assert %{kind: :pr_changes_requested, text: "asked for changes on", link: ^link} =
             one(%{note: "Changes requested on PR #171 (abc1234): Fix it"})
  end

  test "an unknown note gets a generic line without its text" do
    e = one(%{note: "Something new and private"})
    assert %{kind: :other, text: "updated the card"} = e
    refute inspect(e) =~ "private"
  end

  test "comments are one line each, without the text" do
    i =
      idea([], %{comments: [%{author: "hakan@x", body: "Top secret comment", inserted_at: at(5)}]})

    assert [%{kind: :comment, actor: "hakan@x", text: "commented"} = e] = History.entries(i)
    refute inspect(e) =~ "secret"
  end
end
