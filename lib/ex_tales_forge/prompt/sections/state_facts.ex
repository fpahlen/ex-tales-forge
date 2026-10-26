defmodule TalesForge.Prompt.Sections.StateFacts do
  @moduledoc """
  The character's coins and pack (`TalesForge.Game.StateFacts`), with the rule
  to answer the player's questions about them from these facts.
  """
  use TalesForge.Prompt.Section, id: :state_facts, slot: :turn

  alias TalesForge.Game.StateFacts

  @impl true
  def render(ctx) do
    facts = StateFacts.build(get_in(ctx.data, [:world_state, "character"]) || %{})

    Enum.join(
      [
        "## Your character now (from the server; when the player asks about their " <>
          "own coins or pack, answer from these facts and do not invent)"
        | Enum.map(StateFacts.lines(facts), &("- " <> &1))
      ],
      "\n"
    )
  end
end
