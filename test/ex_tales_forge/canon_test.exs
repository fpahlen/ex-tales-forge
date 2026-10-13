defmodule TalesForge.CanonTest do
  use TalesForge.DataCase, async: false

  alias TalesForge.Canon
  alias TalesForge.GameSessions
  alias TalesForge.Repo
  alias TalesForge.Schemas.GameSession
  alias TalesForge.World

  setup do
    Application.put_env(:ex_tales_forge, :canon_stub_pid, self())

    on_exit(fn ->
      Application.delete_env(:ex_tales_forge, :canon_stub_pid)
      Application.delete_env(:ex_tales_forge, :canon_stub_reply)
    end)

    {:ok, session} =
      GameSessions.create_session(%{name: "Canon", adventure_id: "tin_valley"})

    World.store_facts(
      session.id,
      [
        {"valley_inn",
         %{"kind" => "fact", "text" => "The inn has a blue door.", "source" => "narration"}},
        {"sky_island",
         %{"kind" => "fact", "text" => "An island floats over the cut.", "source" => "narration"}}
      ],
      5
    )

    %{session: Repo.get!(GameSession, session.id)}
  end

  test "a fresh session shows only its play facts, and the free text gets one Jev label", %{
    session: session
  } do
    Application.put_env(:ex_tales_forge, :canon_stub_reply, fn items ->
      Map.new(items, &{&1.key, "conflict"})
    end)

    review = Canon.review(session)

    assert review.labels == :ok
    assert [fact, free] = review.differences
    assert {fact.kind, fact.entity_id} == {:new_fact, "valley_inn"}
    assert {free.kind, free.entity_id, free.label} == {:free_text, "sky_island", "conflict"}
    assert_received {:canon_classify, [%{entity_id: "sky_island"}]}
    refute_received {:canon_classify, _}
  end

  test "a label outside the fixed set becomes other", %{session: session} do
    Application.put_env(:ex_tales_forge, :canon_stub_reply, fn items ->
      Map.new(items, &{&1.key, "A grand new legend of the sky"})
    end)

    assert [_, %{label: "other"}] = Canon.review(session).differences
  end

  test "a failed Jev call keeps the rows without a label", %{session: session} do
    Application.put_env(:ex_tales_forge, :canon_stub_reply, {:error, :timeout})

    review = Canon.review(session)
    assert review.labels == :error
    assert [_, %{kind: :free_text, label: nil}] = review.differences
  end

  test "each decision is stored, and the session stays the same", %{session: session} do
    [fact, free] = Canon.review(session).differences
    before = Repo.get!(GameSession, session.id)
    facts_before = World.stored_facts(session.id)

    assert {:ok, kept} = Canon.decide(session, fact, "session_only", "founder@example.com")
    assert kept.seed_patch == nil
    assert {:ok, error} = Canon.decide(session, free, "error", "founder@example.com")
    assert error.seed_patch == nil

    assert Repo.get!(GameSession, session.id).world_state == before.world_state
    assert World.stored_facts(session.id) == facts_before
    assert %{"session_only" => 1, "error" => 1} = count_actions(session.id)
  end

  test "add to canon stores a proposed seed patch and writes no seed file", %{session: session} do
    [fact, _free] = Canon.review(session).differences

    seed_file =
      Path.join(:code.priv_dir(:ex_tales_forge), "adventures/tin_valley/world_agents.json")

    seed_before = File.read!(seed_file)

    assert {:ok, decision} = Canon.decide(session, fact, "add_to_canon", "founder@example.com")

    assert decision.seed_patch =~ "priv/adventures/tin_valley/world_agents.json"
    assert decision.seed_patch =~ "The inn has a blue door."
    assert File.read!(seed_file) == seed_before
  end

  test "a new decision on the same row replaces the old one", %{session: session} do
    [fact, _] = Canon.review(session).differences

    {:ok, _} = Canon.decide(session, fact, "error", "founder@example.com")
    {:ok, _} = Canon.decide(session, fact, "add_to_canon", "other@example.com")

    assert [%{action: "add_to_canon", founder: "other@example.com"}] =
             Map.values(Canon.decisions(session.id))
  end

  test "a decision needs a founder email and a known action", %{session: session} do
    [fact, _] = Canon.review(session).differences

    assert {:error, _} = Canon.decide(session, fact, "session_only", nil)
    assert {:error, _} = Canon.decide(session, fact, "publish", "founder@example.com")
    assert Canon.decisions(session.id) == %{}
  end

  defp count_actions(session_id) do
    session_id |> Canon.decisions() |> Map.values() |> Enum.frequencies_by(& &1.action)
  end
end
