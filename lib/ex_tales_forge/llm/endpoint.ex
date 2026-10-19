defmodule TalesForge.LLM.Endpoint do
  @moduledoc """
  Where an OpenAI-compatible call of `TalesForge.LLM` goes: the base URL and
  the API key.
  """

  @enforce_keys [:base_url, :api_key]
  defstruct [:base_url, :api_key]

  @type t :: %__MODULE__{base_url: String.t(), api_key: String.t()}
end
