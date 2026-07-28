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
  @default_xai_model "grok-4.20-0309-non-reasoning"

  def xai_model, do: System.get_env("XAI_MODEL", @default_xai_model)
  def default_xai_model, do: @default_xai_model

  def tier1_model, do: blank_to_nil(System.get_env("TIER1_MODEL"))
  def tier2_model, do: blank_to_nil(System.get_env("TIER2_MODEL"))

  def tier1_temperature, do: env_float("TIER1_TEMPERATURE", 0.0)
  def tier2_temperature, do: env_float("TIER2_TEMPERATURE", 0.7)
  def tier1_confidence_threshold, do: env_float("TIER1_CONFIDENCE_THRESHOLD", 0.75)
  def tier1_heuristic_threshold, do: env_float("TIER1_HEURISTIC_THRESHOLD", 0.85)
  def tier1_max_tokens, do: env_int("TIER1_MAX_TOKENS", 400)
  def tier2_max_tokens, do: env_int("TIER2_MAX_TOKENS", 700)

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

  defp env_int(key, default) do
    case System.get_env(key) do
      nil -> default
      value -> String.to_integer(value)
    end
  rescue
    ArgumentError -> default
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

  # Tigris (S3-compatible) for Phase 2 images
  def tigris_access_key, do: System.get_env("AWS_ACCESS_KEY_ID", "")
  def tigris_secret_key, do: System.get_env("AWS_SECRET_ACCESS_KEY", "")
  def tigris_endpoint, do: System.get_env("AWS_ENDPOINT_URL_S3", "https://fly.storage.tigris.dev")
  def tigris_bucket, do: System.get_env("BUCKET_NAME", "tales-forge-images")
  # optional CDN base, e.g. https://<bucket>.tigris.dev
  def public_url_base, do: System.get_env("PUBLIC_URL_BASE", "")

  def tigris_configured? do
    present?(tigris_access_key()) and present?(tigris_secret_key())
  end

  # Image generation provider.
  # Grok/xAI ("xai") is the default image generator when XAI_API_KEY is present.
  def image_provider do
    case blank_to_nil(System.get_env("IMAGE_PROVIDER")) do
      nil ->
        if present?(xai_api_key()), do: "xai", else: "mock"

      value ->
        String.downcase(value)
    end
  end

  def xai_base, do: System.get_env("XAI_BASE_URL", "https://api.x.ai/v1")

  def xai_image_model, do: System.get_env("XAI_IMAGE_MODEL", "grok-2-image")
end
