defmodule TalesForge.CharacterCreation.FromText.Adapter do
  @moduledoc """
  The AI call behind `TalesForge.CharacterCreation.FromText`. The default
  adapter is `TalesForge.CharacterCreation.FromText.LLMAdapter`. Tests set a
  different adapter with config `:ex_tales_forge, :character_text_adapter`.
  """

  @doc """
  Reads a character description. Returns the reply map of
  `TalesForge.LLM.complete_character_text/3`.
  """
  @callback read(system :: String.t(), user :: String.t()) :: {:ok, map()} | {:error, term()}
end
