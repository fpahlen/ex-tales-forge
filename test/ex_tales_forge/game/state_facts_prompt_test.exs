defmodule TalesForge.Game.StateFactsPromptTest do
  @moduledoc """
  Card 1 (b): the GM sees the character's coins and pack as plain facts with
  the rule to answer from them. In the h-qa13 replay on playtest v420 the GM
  dodged "what does my pack contain?" though the sheet held a travel cloak and
  a hunting knife.
  """
  use TalesForge.DataCase, async: false

  alias TalesForge.Game.Context
  alias TalesForge.Game.Prompts.GmTurn
  alias TalesForge.Game.Schemas.{HandlerResult, PlayerAction, SingleAction}
  alias TalesForge.GameSessions
  alias TalesForge.Prompt.Assemble

  @question "What did I order earlier and what does my pack contain?"

  setup do
    {:ok, session} = GameSessions.create_session(%{name: "Card 1 (b)"})

    world =
      session.world_state
      |> put_in(["character", "coins"], %{"silver" => 49, "copper" => 8})
      |> put_in(["character", "inventory"], [
        %{"id" => "travel_cloak", "name" => "travel cloak"},
        %{"id" => "hunting_knife", "name" => "hunting knife"}
      ])

    %{text: gm_text(%{session | world_state: world})}
  end

  test "h-qa13: the GM's turn has the pack and coins as facts, with the rule", %{text: text} do
    [_before, facts] = String.split(text, "## Your character now")
    assert facts =~ "- Coins: 0g 49s 8c"
    assert facts =~ "- Pack: travel cloak, hunting knife"
    assert facts =~ "answer from these facts"
  end

  test "the facts come right before the validated action", %{text: text} do
    [_before, facts_on] = String.split(text, "## Your character now")
    [facts, action] = String.split(facts_on, "Validated player action (turn 2)")
    refute facts =~ "Earlier turns (already resolved):"
    assert action =~ @question
  end

  test "the coins and the pack are stated once, not also as JSON", %{text: text} do
    assert text |> String.split("hunting knife") |> length() == 2
    refute text =~ "Player inventory:"
    refute text =~ ~s("coins")
  end

  defp gm_text(session) do
    session
    |> Context.build_gm_context()
    |> Assemble.gm_messages(%GmTurn{
      mechanical: nil,
      player_action: %PlayerAction{
        overall_intent: @question,
        action: %SingleAction{action_type: :other}
      },
      handler: %HandlerResult{handler: "other"},
      turn_number: 2
    })
    |> Enum.map_join("\n", & &1.content)
  end
end
