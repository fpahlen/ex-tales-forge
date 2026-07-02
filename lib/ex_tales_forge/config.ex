defmodule TalesForge.Config do
  @moduledoc """
  Runtime configuration loaded from environment variables.
  """

  def llm_provider do
    case blank_to_nil(System.get_env("LLM_PROVIDER")) do
      nil -> auto_provider()
      value -> String.downcase(value)
    end
  end

  def xai_api_key, do: System.get_env("XAI_API_KEY", "")
  def openai_api_key, do: System.get_env("OPENAI_API_KEY", "")
  def anthropic_api_key, do: System.get_env("ANTHROPIC_API_KEY", "")
  def xai_model, do: System.get_env("XAI_MODEL", "grok-4.3")

  def tier1_model, do: blank_to_nil(System.get_env("TIER1_MODEL"))
  def tier2_model, do: blank_to_nil(System.get_env("TIER2_MODEL"))

  def tier1_temperature, do: env_float("TIER1_TEMPERATURE", 0.0)
  def tier2_temperature, do: env_float("TIER2_TEMPERATURE", 0.7)
  def tier1_confidence_threshold, do: env_float("TIER1_CONFIDENCE_THRESHOLD", 0.75)

  def ollama_api_base, do: System.get_env("OLLAMA_API_BASE", "http://localhost:11434")
  def log_level, do: System.get_env("LOG_LEVEL", "info")

  defp auto_provider do
    cond do
      present?(xai_api_key()) -> "xai"
      present?(openai_api_key()) -> "openai"
      present?(anthropic_api_key()) -> "anthropic"
      true -> "mock"
    end
  end

  defp env_float(key, default) do
    case System.get_env(key) do
      nil -> default
      value -> String.to_float(value)
    end
  rescue
    ArgumentError -> default
  end

  defp blank_to_nil(""), do: nil
  defp blank_to_nil(value), do: value

  defp present?(value), do: is_binary(value) and String.trim(value) != ""
end
