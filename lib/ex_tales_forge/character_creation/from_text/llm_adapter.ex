defmodule TalesForge.CharacterCreation.FromText.LLMAdapter do
  @moduledoc """
  The default `TalesForge.CharacterCreation.FromText.Adapter`: one call to
  `TalesForge.LLM.complete_character_text/3`. That call writes the ai_calls row.
  """
  @behaviour TalesForge.CharacterCreation.FromText.Adapter

  @impl true
  def read(system, user), do: TalesForge.LLM.complete_character_text(system, user)
end
