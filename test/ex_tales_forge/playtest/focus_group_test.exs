defmodule TalesForge.Playtest.FocusGroupTest do
  use TalesForge.DataCase, async: false

  alias TalesForge.Playtest.{FocusGroup, Personas}
  alias TalesForge.Playtest.FocusGroup.{Brief, Questions, Report}

  setup do
    Application.put_env(:ex_tales_forge, :focus_group_enabled, true)
    on_exit(fn -> Application.delete_env(:ex_tales_forge, :focus_group_enabled) end)
  end

  defp reply_for(user) do
    ids = Regex.scan(~r/^- (\w+): /m, user) |> Enum.map(fn [_, id] -> id end)

    %{
      "answers" =>
        Enum.map(ids, &%{"q_id" => &1, "text" => "Answer to #{&1}."}) ++
          [%{"q_id" => "made_up", "text" => "dropped"}],
      "top_improvements" => ["More danger and a real fight early", "Let NPCs remember me", "x"],
      "quit_risks" => ["Nothing happens for ten turns", "Free bread again", "a third one"]
    }
  end

  defp stub_llm(system, user, _opts) do
    send(self(), {:llm_call, system})
    {:ok, reply_for(user)}
  end

  describe "questions" do
    test "the bank has five fixed questions and each persona gets at most one probe" do
      assert length(Questions.bank()) == 5

      for id <- FocusGroup.persona_ids() do
        {:ok, persona} = Personas.fetch(id)
        qs = Questions.for_persona(persona)
        assert length(qs) in 5..8
        assert Enum.count(qs, &(&1.id == "probe")) <= 1
      end
    end

    test "Ronny gets the red-team probe" do
      {:ok, ronny} = Personas.fetch("ronny")
      assert %{id: "probe", text: text} = List.last(Questions.for_persona(ronny))
      assert text =~ "red team"
    end
  end

  describe "brief" do
    test "the gap list parses" do
      gaps = Brief.gaps()
      assert length(gaps) >= 5
      assert Enum.all?(gaps, &(&1.keywords != []))
    end

    test "the brief stays under the hard token cap" do
      {:ok, hawk} = Personas.fetch("hawk")
      brief = Brief.build(hawk, session_summary: String.duplicate("long transcript ", 5_000))
      assert Brief.tokens(brief) <= Brief.max_tokens()
      assert brief =~ "Real danger"
    end

    test "without a finished run the summary says so" do
      assert Brief.last_session_summary("hawk") =~ "No finished playtest run"
    end
  end

  describe "run/1" do
    test "is off unless the flag is on" do
      Application.put_env(:ex_tales_forge, :focus_group_enabled, false)
      assert {:error, :disabled} = FocusGroup.run(llm: &stub_llm/3)
      refute_received {:llm_call, _}
    end

    test "makes one call per persona and checks the typed reply" do
      assert {:ok, interviews, []} =
               FocusGroup.run(llm: &stub_llm/3, session_summary: "A quiet night at the inn.")

      assert Enum.map(interviews, & &1.persona.id) == ~w(hawk paul lotta lars ronny)

      for _ <- 1..5, do: assert_received({:llm_call, _})
      refute_received {:llm_call, _}

      ronny = List.last(interviews)
      assert ronny.red_team
      refute Enum.any?(ronny.answers, &(&1.q_id == "made_up"))
      assert length(ronny.top_improvements) == 3
      assert length(ronny.quit_risks) == 2
    end

    test "the system prompt reuses the persona notes and marks the red team" do
      {:ok, _, _} = FocusGroup.run(llm: &stub_llm/3, personas: ["ronny"], session_summary: "-")
      assert_received {:llm_call, system}
      {:ok, ronny} = Personas.fetch("ronny")
      assert system =~ ronny.notes
      assert system =~ "red team"
    end

    test "a failed call is listed and the others go on" do
      llm = fn
        system, user, opts ->
          if system =~ "You are Paul,", do: {:error, :timeout}, else: stub_llm(system, user, opts)
      end

      assert {:ok, interviews, [{"paul", :timeout}]} =
               FocusGroup.run(llm: llm, session_summary: "-")

      assert length(interviews) == 4
    end

    test "the default LLM is the mock in tests" do
      assert {:ok, [hawk], []} = FocusGroup.run(personas: ["hawk"], session_summary: "-")
      assert length(hawk.answers) == 5
    end
  end

  describe "decode/2" do
    test "a reply without answers is an error" do
      assert {:error, {:no_answers, _}} = FocusGroup.decode(%{"answers" => []}, ["good"])
      assert {:error, {:invalid_reply, _}} = FocusGroup.decode(%{"x" => 1}, ["good"])
    end
  end

  describe "report" do
    setup do
      {:ok, interviews, _} = FocusGroup.run(llm: &stub_llm/3, session_summary: "-")
      %{interviews: interviews}
    end

    test "themes group improvements by product gap", %{interviews: interviews} do
      themes = FocusGroup.themes(interviews)
      ids = Enum.map(themes, fn {gap, _} -> gap.id end)
      assert "danger" in ids
      assert "callbacks" in ids
      assert List.last(ids) == "other"
    end

    test "the markdown has every persona and labels Ronny", %{interviews: interviews} do
      md = Report.markdown(interviews, [{"lars", :timeout}], date: ~D[2026-10-15])
      assert md =~ "# Persona focus group, 2026-10-15"
      assert md =~ "## Ronny (red team)"
      for name <- ~w(Hawk Paul Lotta Lars), do: assert(md =~ "## #{name}")
      assert md =~ "lars: `:timeout`"
    end

    test "the digest is short and names the path", %{interviews: interviews} do
      d = Report.digest(interviews, [], "docs/research/focus-group-2026-10-15.md")
      assert d =~ "5 of 5 personas answered"
      assert d =~ "docs/research/focus-group-2026-10-15.md"
      assert String.length(d) < 400
    end
  end
end
