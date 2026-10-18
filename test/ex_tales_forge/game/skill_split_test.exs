defmodule TalesForge.Game.SkillSplitTest do
  @moduledoc """
  Skill split (`SKILL_SPLIT`): the turn rolls each part with injected rolls,
  refuses a split below the threshold in the story, banks one learning
  chance at most, and changes nothing with the flag off.
  """
  use TalesForge.DataCase, async: false

  alias TalesForge.Game.JevIntent
  alias TalesForge.Game.Mechanics
  alias TalesForge.Game.Schemas.{HandlerResult, MechanicalResolution, PlayerAction, SingleAction}
  alias TalesForge.Game.SkillSplit
  alias TalesForge.Game.Turn
  alias TalesForge.GameSessions

  doctest SkillSplit

  @off %{
    turn_outcome_record: false,
    npc_dialogue_memory: false,
    npc_reactions: false,
    world_agents: false,
    turn_premise_first: false,
    turn_state_from_mechanics: false,
    turn_apply_outcomes: false,
    history_strip_injection: false,
    skill_detail_level: false,
    skill_split: false
  }

  setup do
    {:ok, session} = GameSessions.create_session(%{name: "Split", adventure_id: "tin_valley"})
    %{session: session}
  end

  defp with_skill(session, level) do
    world =
      session.world_state
      |> put_in(["character", "skills"], %{"melee_combat" => level})
      |> put_in(["character", "stats"], %{"STR" => 10, "DEX" => 10, "CON" => 10})
      |> put_in(["character", "learning_points"], %{})

    %{session | world_state: world}
  end

  defp action(text) do
    %PlayerAction{
      overall_intent: text,
      action: %SingleAction{action_type: :observe, parameters: %{"skill" => "melee_combat"}}
    }
  end

  defp turn(session, text, flags, rolls) do
    Turn.new({session, 1}, {text, action(text)},
      flags: Map.merge(@off, flags),
      role: :playtest,
      rolls: rolls
    )
  end

  defp played(session, text, flags, rolls) do
    session
    |> turn(text, flags, rolls)
    |> Turn.Mechanics.apply()
    |> Turn.Prompt.build()
  end

  defp per_turn(t), do: List.last(t.prompt.messages).content

  defp all_text(t), do: Enum.map_join(t.prompt.messages, "\n", & &1.content)

  describe "flag on" do
    test "two parts: the server rolls each part with the injected rolls", %{session: session} do
      t = session |> with_skill(100) |> played("I attack twice", %{skill_split: true}, [12, 60])

      mech = t.outcome.mechanical
      assert [%{"level" => 50, "roll" => 12}, %{"level" => 50, "roll" => 60}] = mech.parts
      assert Enum.map(mech.parts, & &1["outcome"]) == ["success", "partial_success"]
      assert mech.outcome == "success"
      assert per_turn(t) =~ "## Skill split (rolled by the server)"
      assert per_turn(t) =~ "- Part 1: level 50, roll 12, result success"
      assert per_turn(t) =~ "- Part 2: level 50, roll 60, result partial_success"
      assert all_text(t) =~ "## Skill split"
      refute all_text(t) =~ "at -10 skill per extra action"
      refute all_text(t) =~ "skill_split:on"
    end

    test "three parts at 150 and above", %{session: session} do
      t =
        session
        |> with_skill(160)
        |> played("I make three attacks", %{skill_split: true}, [10, 30, 80])

      assert Enum.map(t.outcome.mechanical.parts, & &1["level"]) == [54, 53, 53]

      assert Enum.map(t.outcome.mechanical.parts, & &1["outcome"]) ==
               ["success", "success", "failure"]

      assert per_turn(t) =~ "- Part 3: level 53, roll 80, result failure"
    end

    test "uneven parts from the player text", %{session: session} do
      t =
        session
        |> with_skill(150)
        |> played("two cuts, a strong one at 95 and a quick jab at 55", %{skill_split: true}, [
          4,
          5
        ])

      assert Enum.map(t.outcome.mechanical.parts, & &1["level"]) == [95, 55]
    end

    test "below the threshold: one normal roll, and the story tells the refusal",
         %{session: session} do
      t = session |> with_skill(80) |> played("I attack twice", %{skill_split: true}, [7])

      mech = t.outcome.mechanical
      assert mech.parts == nil
      assert mech.roll == 7
      assert mech.split == %{"requested" => 2, "refused" => "below_start"}
      assert per_turn(t) =~ "## Skill split (refused by the server)"
      assert per_turn(t) =~ "this split needs more skill"
    end

    test "three parts below the triple threshold are refused", %{session: session} do
      t = session |> with_skill(120) |> played("three attacks", %{skill_split: true}, [7])
      assert t.outcome.mechanical.split["refused"] == "below_triple"
    end
  end

  describe "learning cap" do
    test "a split action banks one learning chance when every part fails" do
      character = %{
        "skills" => %{"melee_combat" => 160},
        "stats" => %{"STR" => 10},
        "learning_points" => %{}
      }

      handler = %HandlerResult{handler: "observe"}

      {updated, res} =
        SkillSplit.apply(
          character,
          %SkillSplit.Check{
            player_action: action("three attacks"),
            handler: handler,
            text: "three attacks",
            rolls: [80, 80, 80]
          }
        )

      assert length(res.parts) == 3
      assert Enum.all?(res.parts, &(&1["outcome"] != "success"))
      assert res.lp_awarded == 1.0
      assert updated["learning_points"] == %{"melee_combat" => 1.0}
      assert updated["learning_failures"] == %{"melee_combat" => 1}
    end

    test "the turn records one learning chance for the split", %{session: session} do
      t =
        session |> with_skill(160) |> played("three attacks", %{skill_split: true}, [80, 80, 80])

      assert t.outcome.mechanical.lp_awarded == 1.0
    end
  end

  describe "flag off" do
    test "the prompts and the roll do not change", %{session: session} do
      session = with_skill(session, 160)
      off = played(session, "I attack twice", %{}, [12, 20])

      unset =
        Turn.new({session, 1}, {"I attack twice", action("I attack twice")},
          flags: Map.delete(@off, :skill_split),
          role: :playtest
        )

      assert off.outcome.mechanical.parts == nil
      assert off.outcome.mechanical.split == nil

      assert MechanicalResolution.encode(off.outcome.mechanical) |> Map.keys() |> Enum.sort() ==
               ~w(effective_skill improvements lp_awarded notes outcome roll skill)

      text = all_text(off)
      assert text =~ "Multi-Actions"
      refute text =~ "Skill split"
      refute text =~ "skill_split"

      unset_text =
        unset
        |> Map.put(:outcome, off.outcome)
        |> Turn.Prompt.build()
        |> all_text()

      assert unset_text == text
    end

    test "the Jev questions do not change" do
      assert JevIntent.questions([], :v1, false) == JevIntent.questions([], :v1)
      assert Keyword.has_key?(JevIntent.questions([], :v1, true), :split)
    end

    test "the rules text with the flag off is the text before the split rules" do
      rules = TalesForge.Game.Prompts.load_rules("tin_valley")
      off = SkillSplit.rules_text(rules, false)
      on = SkillSplit.rules_text(rules, true)

      assert off =~ "- **Multi-Actions**: Multiple actions per round"
      refute off =~ "<!--"
      refute on =~ "<!--"
      assert on =~ "## Skill split"
      assert on =~ "## Skill Split by Skill Family"
    end
  end

  test "split_levels/2 reads the thresholds from one settings place" do
    settings = %{start: 20, triple: 30, min_uneven_part: 5}
    assert Mechanics.split_levels(20, 2, settings) == {:ok, [10, 10]}
    assert Mechanics.split_levels(30, [19, 11], settings) == {:ok, [19, 11]}
    assert Mechanics.split_levels(29, 3, settings) == {:error, :below_triple}
  end
end
