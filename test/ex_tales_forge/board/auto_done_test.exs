defmodule TalesForge.Board.AutoDoneTest do
  @moduledoc "The board moves Building cards to Done when their PR is in the prod release."
  use TalesForge.DataCase, async: false

  alias TalesForge.Board
  use Oban.Testing, repo: TalesForge.Workflow.Repo, prefix: "workflow"

  alias TalesForge.Board.Workers.AutoDone

  doctest AutoDone

  @ada "ada@example.com"

  # GitHub: PR n merged as m<n>; m1 and m2 are in the running release abc0009,
  # m3 is not. `down: true` makes GitHub answer 503.
  defp github!(opts \\ []) do
    Application.put_env(:ex_tales_forge, :pr_feed_token, "feed-token")
    Application.put_env(:ex_tales_forge, :board_req_options, plug: {Req.Test, __MODULE__})
    System.put_env("GIT_SHA", "abc0009")
    test_pid = self()

    Req.Test.stub(__MODULE__, fn conn ->
      send(test_pid, {:github, conn.request_path})

      cond do
        opts[:down] ->
          Plug.Conn.send_resp(conn, 503, "down")

        (match = Regex.run(~r{/pulls/(\d+)$}, conn.request_path)) &&
            String.to_integer(List.last(match)) in Keyword.get(opts, :open, []) ->
          Req.Test.json(conn, %{"state" => "open", "merged" => false})

        match = Regex.run(~r{/pulls/(\d+)$}, conn.request_path) ->
          Req.Test.json(conn, %{"merged" => true, "merge_commit_sha" => "m#{List.last(match)}"})

        String.ends_with?(conn.request_path, "/compare/m3...abc0009") ->
          Req.Test.json(conn, %{"status" => "behind"})

        String.contains?(conn.request_path, "/compare/") ->
          Req.Test.json(conn, %{"status" => "ahead"})
      end
    end)

    on_exit(fn ->
      Application.delete_env(:ex_tales_forge, :pr_feed_token)
      Application.delete_env(:ex_tales_forge, :board_req_options)
      System.delete_env("GIT_SHA")
    end)
  end

  defp building!(title, pr) do
    {:ok, idea} = Board.create_idea(@ada, %{"title" => title})
    {:ok, idea} = Board.vote(idea, @ada, 1)
    {:ok, idea} = Board.move(idea, {:founder, @ada}, "refining")

    {:ok, idea} =
      Board.refine(idea, %{"open_questions" => [], "rough_cost" => "S", "verdict" => "feasible"})

    {:ok, idea} = Board.move(idea, {:bot, :case}, "check")
    {:ok, idea} = Board.move(idea, {:founder, @ada}, "building")

    if pr do
      {:ok, idea} =
        Board.add_link(idea, "bot:bobby", %{
          "kind" => "pr",
          "url" => "https://github.com/whyse-ab/ex-tales-forge/pull/#{pr}"
        })

      idea
    else
      idea
    end
  end

  test "moves exactly the Building cards whose PR is in the release, as bot:board, once" do
    github!()
    in1 = building!("In release", 1)
    in2 = building!("Also in", 2)
    later = building!("Not yet", 3)
    no_pr = building!("No PR", nil)

    assert {:ok, moved} = AutoDone.run()
    assert Enum.sort(moved) == Enum.sort([in1.id, in2.id])

    done = Board.get_idea!(in1.id)
    assert done.column == "done"
    last = List.last(done.transitions)
    assert {last.from, last.to, last.actor} == {"building", "done", "bot:board"}
    assert last.note == "PR #1 is in the prod release abc0009. The board moved the card to Done."

    assert Board.get_idea!(later.id).column == "building"
    assert Board.get_idea!(no_pr.id).column == "building"

    # Idempotent: a second run moves nothing and writes no new move.
    assert {:ok, []} = AutoDone.run()
    assert length(Board.get_idea!(in1.id).transitions) == length(done.transitions)
  end

  test "GitHub down: nothing moves, the job fails so Oban tries again" do
    github!(down: true)
    card = building!("In release", 1)

    assert {:error, "GitHub did not answer for PR #1. Try again later."} = AutoDone.run()
    assert Board.get_idea!(card.id).column == "building"

    github!()
    assert {:ok, [_]} = AutoDone.run()
    assert Board.get_idea!(card.id).column == "done"
  end

  test "no GIT_SHA: nothing moves, try again later" do
    github!()
    card = building!("In release", 1)
    System.delete_env("GIT_SHA")
    assert {:error, "The board cannot see the prod release" <> _} = AutoDone.run()
    assert Board.get_idea!(card.id).column == "building"
  end

  test "off production the job and the boot hook do nothing; backoff doubles up to 4 h" do
    github!()
    card = building!("In release", 1)
    assert :ok = AutoDone.schedule_on_boot()
    assert :ok = perform_job(AutoDone, %{})
    assert Board.get_idea!(card.id).column == "building"
    assert AutoDone.backoff(%Oban.Job{attempt: 1}) == 60
    assert AutoDone.backoff(%Oban.Job{attempt: 20}) == 4 * 3600
  end

  describe "a PR link added after the deploy (card b18fc8dc)" do
    setup do
      Application.put_env(:ex_tales_forge, :board_auto_done_anywhere, true)
      on_exit(fn -> Application.delete_env(:ex_tales_forge, :board_auto_done_anywhere) end)
    end

    test "the link queues a new run and the card moves to Done without a boot" do
      github!()
      card = building!("Linked late", nil)
      assert Board.get_idea!(card.id).column == "building"

      {:ok, _} =
        Board.add_link(card, "bot:bobby", %{
          "kind" => "pr",
          "url" => "https://github.com/whyse-ab/ex-tales-forge/pull/1"
        })

      done = Board.get_idea!(card.id)
      assert done.column == "done"
      assert List.last(done.transitions).actor == "bot:board"
    end

    test "a PR that is not in the release yet keeps the card in Building" do
      github!()
      card = building!("Linked late", nil)

      {:ok, _} =
        Board.add_link(card, "bot:bobby", %{
          "kind" => "pr",
          "url" => "https://github.com/whyse-ab/ex-tales-forge/pull/3"
        })

      assert Board.get_idea!(card.id).column == "building"
    end

    test "a link that is not a PR queues no run" do
      github!()
      card = building!("Doc only", nil)

      {:ok, _} =
        Board.add_link(card, "bot:bobby", %{"kind" => "doc", "url" => "https://x.test/d"})

      refute_received {:github, _}
      assert Board.get_idea!(card.id).column == "building"
    end
  end

  defp link_pr!(card, number, final) do
    attrs = %{
      "idea_id" => card.id,
      "number" => number,
      "url" => "https://github.com/whyse-ab/ex-tales-forge/pull/#{number}",
      "head_sha" => "sha#{number}",
      "player_note" => "No change for players."
    }

    attrs = if final == :unset, do: attrs, else: Map.put(attrs, "final", final)
    {:ok, card} = Board.link_pr(attrs)
    card
  end

  describe "cards with more than one PR" do
    test "a PR linked without the final flag is final (the one-PR behavior)" do
      github!()
      card = building!("One PR", nil) |> link_pr!(1, :unset)
      assert Board.get_idea!(card.id).pr_final

      assert {:ok, [id]} = AutoDone.run()
      assert id == card.id
    end

    test "a PR with final false keeps the card in Building when it ships" do
      github!()
      card = building!("Part 1 of 2", nil) |> link_pr!(1, false)

      assert {:ok, []} = AutoDone.run()
      assert Board.get_idea!(card.id).column == "building"

      # The last part comes with final true; part 1 is merged, so the card moves.
      link_pr!(card, 2, true)
      assert {:ok, [_]} = AutoDone.run()
      assert Board.get_idea!(card.id).column == "done"
    end

    test "another linked PR that is still open keeps the card in Building" do
      github!(open: [4])
      card = building!("Two PRs", 4) |> link_pr!(1, true)

      assert {:ok, []} = AutoDone.run()
      assert Board.get_idea!(card.id).column == "building"

      github!()
      assert {:ok, [_]} = AutoDone.run()
      assert Board.get_idea!(card.id).column == "done"
    end
  end

  test "two runs at the same time make one move" do
    github!()
    card = building!("In release", 1)

    results =
      1..2
      |> Enum.map(fn _ -> Task.async(fn -> AutoDone.run() end) end)
      |> Enum.map(&Task.await(&1, 15_000))

    assert Enum.sort(results) == [{:ok, []}, {:ok, [card.id]}]

    moves =
      Board.get_idea!(card.id).transitions
      |> Enum.filter(&(&1.from == "building" and &1.to == "done"))

    assert length(moves) == 1
  end

  test "Done wakes no bot" do
    assert TalesForge.Board.Transitions.wakes(Workflow.Team.Source.team(), "building", "done") ==
             [:founders]

    assert TalesForge.Board.Events.bots(Workflow.Team.Source.team(), :idea_to_done, %{}) == []
  end
end
