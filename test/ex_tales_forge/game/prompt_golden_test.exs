defmodule TalesForge.Game.PromptGoldenTest do
  @moduledoc """
  Byte-identical prompts for a fixed session of each adventure.

  The Character plan (tales-forge-docs `docs/plan-unify-character.md`) moves
  player characters and NPCs into one `characters` table in phases. Until a
  phase deliberately changes what the models see, every prompt must stay
  exactly the same: the intent context, the opening-scene request and the GM
  turn messages (narrator, rules, task, session-stable and per-turn parts),
  plus the player character's sheet in `world_state`.

  The golden files in `test/fixtures/prompts/` are one per adventure:
  `<adventure>.txt`. Session ids,
  other UUIDs and timestamps are normalised. To regenerate after an intended
  prompt change, run
  `UPDATE_PROMPT_GOLDEN=1 mix test test/ex_tales_forge/game/prompt_golden_test.exs`
  and review the diff.
  """
  use TalesForge.DataCase, async: false

  alias TalesForge.Game.Context
  alias TalesForge.Game.Prompts
  alias TalesForge.Game.Schemas.{HandlerResult, MechanicalResolution, PlayerAction, SingleAction}
  alias TalesForge.GameSessions
  alias TalesForge.Jido
  alias TalesForge.NPC

  @dir Path.expand("../../fixtures/prompts", __DIR__)

  setup do
    on_exit(fn ->
      for {id, _pid} <- Jido.list_agents(), do: Jido.stop_agent(id)
    end)

    :ok
  end

  for adventure <- ~w(crossroads_ledger tin_valley) do
    test "#{adventure}: prompts are byte-identical to the golden file" do
      check_golden(unquote(adventure))
    end
  end

  for role <- [:production, :playtest] do
    test "tin_valley GM turn for the #{role} role is byte-identical to its golden file" do
      check_role_golden(unquote(role))
    end
  end

  # One golden per prompt flag (`TalesForge.Prompt.Ctx.read_flags/0`). The
  # context holds the data of every flag section; only the flag that is on
  # adds its section. "off" has every flag off.
  for flag <-
        ~w(off turn_outcome_record npc_dialogue_memory npc_reactions world_agents skill_detail_level) do
    test "tin_valley GM turn with the #{flag} flag is byte-identical to its golden file" do
      check_flag_golden(unquote(flag))
    end
  end

  defp check_flag_golden(flag) do
    {:ok, session} = GameSessions.create_session(%{name: "Golden", adventure_id: "tin_valley"})
    context = session |> Context.build_gm_context() |> Map.merge(flag_data())
    present = hd(context.intent_context["present_npcs"])
    context = put_in(context, [:world_state, "npc_memory"], %{present => ["Mind the step."]})

    flags =
      Map.new(
        ~w(turn_outcome_record npc_dialogue_memory npc_reactions world_agents skill_detail_level)a,
        fn f ->
          {f, Atom.to_string(f) == flag}
        end
      )

    actual =
      context
      |> gm_messages(2, "look around", role: :playtest, flags: flags)
      |> messages()
      |> normalise(session.id)

    path = Path.join([@dir, "flags", "tin_valley.#{flag}.txt"])

    if System.get_env("UPDATE_PROMPT_GOLDEN") in ~w(1 true) do
      File.mkdir_p!(Path.dirname(path))
      File.write!(path, actual)
    end

    assert actual == File.read!(path),
           "the GM prompt with #{flag} changed; UPDATE_PROMPT_GOLDEN=1 rewrites #{path}"
  end

  defp flag_data do
    %{
      outcome_record: %{
        "actions" => [%{"type" => "observe", "status" => "accepted"}],
        "coins" => %{"delta_copper" => 0, "after_copper" => 30},
        "items" => %{"gained" => [], "lost" => []},
        "clock" => %{},
        "location" => %{"from" => "valley_inn", "to" => "valley_inn"}
      },
      npc_reactions: [
        %{
          "name" => "Brenna Holt",
          "emotion" => "wary",
          "intensity" => 0.7,
          "stance" => "cool",
          "confidence" => 0.8
        }
      ],
      world_facts: [
        %{
          id: "valley_inn",
          kind: :location,
          name: "Valley Inn",
          role: :here,
          facts: [%{"source" => "pack", "text" => "The common room has one hearth."}]
        }
      ],
      price_lines: ["Price: ale, 2 copper"],
      noticed: %{level: :high, details: ["Under the surface, Brenna Holt is wary."]}
    }
  end

  defp check_role_golden(role) do
    {:ok, session} = GameSessions.create_session(%{name: "Golden", adventure_id: "tin_valley"})
    context = Context.build_gm_context(session)
    variant = if role == :production, do: :lean, else: :full
    schema = TalesForge.LLM.narration_schema(variant)["properties"]

    actual =
      ("===== reply fields =====\n" <>
         Enum.join(Jason.decode!(Jason.encode!(schema)) |> Map.keys() |> Enum.sort(), "\n") <>
         "\n===== gm turn 1 =====\n" <>
         messages(gm_messages(context, 1, "look around", role: role)))
      |> normalise(session.id)

    path = Path.join([@dir, "roles", "tin_valley.#{role}.txt"])

    if System.get_env("UPDATE_PROMPT_GOLDEN") in ~w(1 true) do
      File.mkdir_p!(Path.dirname(path))
      File.write!(path, actual)
    end

    assert actual == File.read!(path),
           "the #{role} GM prompt changed; UPDATE_PROMPT_GOLDEN=1 rewrites #{path}"
  end

  defp check_golden(adventure) do
    {:ok, session} = GameSessions.create_session(%{name: "Golden", adventure_id: adventure})

    actual = render(session)
    path = Path.join(@dir, "#{adventure}.txt")

    if System.get_env("UPDATE_PROMPT_GOLDEN") in ~w(1 true) do
      File.mkdir_p!(@dir)
      File.write!(path, actual)
    end

    expected = File.read!(path)

    assert actual == expected,
           "prompts for #{adventure} changed; diff #{path} against a fresh render " <>
             "(UPDATE_PROMPT_GOLDEN=1 rewrites it)"
  end

  defp render(session) do
    context = Context.build_gm_context(session)
    present = Map.get(context.intent_context, "present_npcs", [])

    sections = [
      {"world_state.character", Jason.encode!(session.world_state["character"], pretty: true)},
      {"intent context",
       session |> Context.build_intent_context() |> Context.format_intent_context()},
      {"npc gm sections", NPC.format_gm_sections(session.id, present)},
      {"scene messages", messages(Prompts.scene_messages(context))},
      {"gm turn 1", messages(gm_messages(context, 1, "look around"))},
      {"gm turn 4", messages(gm_messages(context, 4, "ask about the road"))}
    ]

    sections
    |> Enum.map_join("\n", fn {title, body} -> "===== #{title} =====\n#{body}\n" end)
    |> normalise(session.id)
  end

  defp gm_messages(context, turn_number, text, opts \\ []) do
    player_action = %PlayerAction{
      overall_intent: text,
      action: %SingleAction{action_type: :observe, target: nil}
    }

    Prompts.gm_messages(
      context,
      %MechanicalResolution{skill: "insight", roll: 14, outcome: "success"},
      player_action,
      %HandlerResult{handler: "observe", skill: "insight"},
      turn_number,
      opts
    )
  end

  defp messages(list) do
    Enum.map_join(list, "\n", fn m -> "--- #{m.role} ---\n#{m.content}" end)
  end

  defp normalise(text, session_id) do
    text
    |> String.replace(session_id, "<SESSION>")
    |> String.replace(~r/[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}/, "<UUID>")
    |> String.replace(~r/\d{4}-\d{2}-\d{2}[T ]\d{2}:\d{2}:\d{2}(\.\d+)?Z?/, "<TS>")
  end
end
