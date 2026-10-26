defmodule TalesForge.PromptTest do
  @moduledoc "The prompt pipeline (`TalesForge.Prompt`) and the narration profile."
  use ExUnit.Case, async: true

  alias TalesForge.Prompt
  alias TalesForge.Prompt.{Ctx, Profile, Sections}

  doctest Sections.WorldFacts
  doctest Sections.Prices
  doctest Sections.CharacterReactions
  doctest Sections.Gestures
  doctest Sections.OutcomeRecord
  doctest Sections.Premise
  doctest Sections.NoticedDetails

  defmodule StaticA do
    @moduledoc false
    use TalesForge.Prompt.Section, id: :static_a, slot: :static
    @impl true
    def render(_ctx), do: "A"
  end

  defmodule SessionB do
    @moduledoc false
    use TalesForge.Prompt.Section, id: :session_b, slot: :session
    @impl true
    def render(_ctx), do: "B"
  end

  defmodule TurnC do
    @moduledoc false
    use TalesForge.Prompt.Section, id: :turn_c, slot: :turn
    @impl true
    def render(%{data: data}), do: data[:c]
  end

  defmodule TurnTail do
    @moduledoc false
    use TalesForge.Prompt.Section, id: :turn_tail, slot: :turn
    @impl true
    def glue, do: ""
    @impl true
    def render(_ctx), do: "+tail"
  end

  defmodule Never do
    @moduledoc false
    use TalesForge.Prompt.Section, id: :never, slot: :turn
    @impl true
    def applies?(_ctx), do: false
    @impl true
    def render(_ctx), do: "never"
  end

  test "to_messages keeps the cache order static < session < turn" do
    messages =
      %Ctx{data: %{c: "C"}}
      |> Prompt.new()
      |> Prompt.add(TurnC)
      |> Prompt.add(Never)
      |> Prompt.add(SessionB)
      |> Prompt.add(StaticA)
      |> Prompt.add(TurnTail)
      |> Prompt.to_messages()

    assert messages == [
             %{role: "system", content: "A"},
             %{role: "user", content: "B"},
             %{role: "user", content: "C+tail"}
           ]
  end

  test "a section that renders nil is left out, and the glue follows the section" do
    prompt = %Ctx{data: %{c: nil}} |> Prompt.new() |> Prompt.add_all([TurnC, TurnTail])
    assert Prompt.render_slot(prompt, :turn) == "+tail"
    assert Prompt.ids(prompt) == [:turn_c, :turn_tail]
  end

  test "the narration profiles list their sections" do
    gm = Profile.sections(%Ctx{call: :gm}) |> Enum.map(& &1.id())
    scene = Profile.sections(%Ctx{call: :scene}) |> Enum.map(& &1.id())

    assert Enum.take(gm, 5) == [:narrator, :rules, :task, :character_sheet, :opening]
    assert List.last(gm) == :gm_turn_action
    assert scene == gm -- [:gm_turn_action]
  end

  describe "Profile.ids/1" do
    @static ~w(narrator rules task)a
    @off %{
      turn_outcome_record: false,
      npc_dialogue_memory: false,
      npc_reactions: false,
      world_agents: false,
      skill_detail_level: false,
      location_grid: false
    }

    defp ids(call, flags),
      do: Profile.ids(%Ctx{call: call, flags: Map.merge(@off, flags)})

    test "every flag off" do
      assert ids(:gm, %{}) ==
               @static ++
                 ~w(character_sheet opening perceived_facts intent_context npcs gestures scene_now premise fallen rest_growth player_request state_facts gm_turn_action)a

      assert ids(:scene, %{}) == ids(:gm, %{}) -- [:gm_turn_action]
    end

    test "each flag adds its own sections" do
      base = ids(:gm, %{})

      for {flag, added} <- [
            turn_outcome_record: [:outcome_record],
            npc_dialogue_memory: [:npc_memory],
            npc_reactions: [:npc_reactions],
            world_agents: [:world_facts, :prices, :npc_reactions],
            skill_detail_level: [:noticed_details]
          ] do
        assert Enum.sort(ids(:gm, %{flag => true}) -- base) == Enum.sort(added)
      end
    end

    test "every flag on keeps the prompt order" do
      on = Map.new(@off, fn {k, _} -> {k, true} end)

      assert ids(:gm, on) ==
               @static ++
                 ~w(character_sheet opening perceived_facts intent_context npcs world_facts prices npc_reactions npc_memory gestures scene_now surroundings outcome_record noticed_details premise fallen rest_growth player_request state_facts gm_turn_action)a
    end
  end
end
