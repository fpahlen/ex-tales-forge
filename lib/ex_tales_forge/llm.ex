defmodule TalesForge.LLM do
  @moduledoc """
  Two-tier LLM client with mock fallback and JSON validation retry.
  """

  require Logger

  alias TalesForge.Config

  alias TalesForge.Game.Schemas.{
    GMStructuredResponse,
    HandlerResult,
    IntentExtraction,
    MechanicalResolution,
    PlayerAction
  }

  @intent_schema %{
    "type" => "object",
    "required" => ["overall_intent", "actions"],
    "properties" => %{
      "overall_intent" => %{"type" => "string"},
      "actions" => %{"type" => "array", "minItems" => 1},
      "primary_index" => %{"type" => "integer"},
      "confidence" => %{"type" => "number"},
      "needs_clarification" => %{"type" => "boolean"},
      "clarification_question" => %{"type" => ["string", "null"]},
      "clarification_options" => %{"type" => "array"}
    }
  }

  @gm_schema %{
    "type" => "object",
    "required" => ["narrative"],
    "properties" => %{
      "narrative" => %{"type" => "string"},
      "mechanical_resolution" => %{"type" => "object"},
      "state_updates" => %{"type" => "array"},
      "npc_memory_updates" => %{"type" => "array"},
      "overlay_deltas" => %{"type" => "object"},
      "context_summary" => %{"type" => ["string", "null"]}
    }
  }

  def provider, do: Config.llm_provider()

  def llm_source("mock"), do: "mock"
  def llm_source(_), do: "api"

  def complete_intent(system, user) do
    model = tier1_model()

    if model == "mock" do
      {:error, :mock_intent}
    else
      complete_json(model, system, user, @intent_schema, Config.tier1_temperature())
      |> case do
        {:ok, map} -> {:ok, IntentExtraction.decode(map)}
        error -> error
      end
    end
  end

  def complete_turn(
        system,
        user,
        %PlayerAction{} = player_action,
        %HandlerResult{} = handler,
        turn_number
      ) do
    model = tier2_model()

    if model == "mock" do
      {:ok, mock_turn_response(player_action, handler, turn_number)}
    else
      user_prompt =
        user <>
          "\n\nValidated player action (turn #{turn_number}):\n" <>
          Jason.encode!(PlayerAction.encode(player_action), pretty: true) <>
          "\n\nAction handler result:\n" <>
          Jason.encode!(handler_payload(handler), pretty: true)

      complete_json(model, system, user_prompt, @gm_schema, Config.tier2_temperature())
      |> case do
        {:ok, map} -> {:ok, GMStructuredResponse.decode(map)}
        error -> error
      end
    end
  end

  defp handler_payload(%HandlerResult{} = handler) do
    %{
      "handler" => handler.handler,
      "skill" => handler.skill,
      "target" => handler.target,
      "notes" => handler.notes
    }
  end

  defp mock_turn_response(
         %PlayerAction{} = player_action,
         %HandlerResult{} = handler,
         turn_number
       ) do
    skill = handler.skill || Map.get(player_action.action.parameters, "skill")

    %GMStructuredResponse{
      narrative:
        "**Turn #{turn_number}** — The world reacts to your action.\n\n" <>
          "#{player_action.overall_intent}\n\n" <>
          "_Mock GM: set XAI_API_KEY for full LLM narration._",
      mechanical_resolution: %MechanicalResolution{
        skill: skill && to_string(skill),
        outcome: "none"
      }
    }
  end

  defp complete_json(model, system, user, schema, temperature) do
    user_with_schema =
      user <>
        "\n\nReturn JSON matching this schema:\n" <>
        Jason.encode!(schema, pretty: true)

    with {:ok, raw} <- dispatch(model, system, user_with_schema, temperature),
         {:ok, map} <- parse_json(raw) do
      {:ok, map}
    else
      {:error, :invalid_json} ->
        retry_user =
          "Your previous response was invalid. Return ONLY valid JSON matching the schema.\n\n" <>
            user_with_schema

        with {:ok, raw} <- dispatch(model, system, retry_user, temperature),
             {:ok, map} <- parse_json(raw) do
          {:ok, map}
        end

      error ->
        error
    end
  end

  defp dispatch("mock", _system, _user, _temp), do: {:error, :mock_model}

  defp dispatch(model, system, user, temperature) do
    started = System.monotonic_time(:millisecond)
    provider = provider()

    Logger.info("llm call start provider=#{provider} model=#{model} temp=#{temperature}")

    result =
      cond do
        String.starts_with?(model, "xai/") or provider == "xai" ->
          call_openai_compatible(
            model,
            system,
            user,
            temperature,
            xai_base(),
            Config.xai_api_key()
          )

        String.starts_with?(model, "gpt-") or provider == "openai" ->
          call_openai_compatible(
            model,
            system,
            user,
            temperature,
            openai_base(),
            Config.openai_api_key()
          )

        String.starts_with?(model, "ollama/") ->
          call_ollama(model, system, user, temperature)

        true ->
          {:error, {:unsupported_model, model}}
      end

    case result do
      {:ok, content} ->
        elapsed = System.monotonic_time(:millisecond) - started

        Logger.info(
          "llm call done provider=#{provider} model=#{model} duration_ms=#{elapsed} chars=#{String.length(content)}"
        )

        {:ok, content}

      error ->
        error
    end
  end

  defp call_openai_compatible(model, system, user, temperature, base_url, api_key) do
    if String.trim(api_key) == "" do
      {:error, :missing_api_key}
    else
      clean_model =
        model |> String.replace_prefix("xai/", "") |> String.replace_prefix("openai/", "")

      Req.post(
        base_url <> "/chat/completions",
        headers: [{"authorization", "Bearer " <> api_key}, {"content-type", "application/json"}],
        json: %{
          model: clean_model,
          temperature: temperature,
          response_format: %{type: "json_object"},
          messages: [
            %{role: "system", content: system},
            %{role: "user", content: user}
          ]
        },
        receive_timeout: 120_000
      )
      |> case do
        {:ok, %{status: 200, body: %{"choices" => [%{"message" => %{"content" => content}} | _]}}} ->
          {:ok, content || "{}"}

        {:ok, %{status: status, body: body}} ->
          {:error, {:api_error, status, body}}

        {:error, reason} ->
          {:error, reason}
      end
    end
  end

  defp call_ollama(model, system, user, temperature) do
    clean = String.replace_prefix(model, "ollama/", "")
    base = String.trim_trailing(Config.ollama_api_base(), "/")

    Req.post(
      base <> "/api/chat",
      json: %{
        model: clean,
        stream: false,
        options: %{temperature: temperature},
        messages: [
          %{role: "system", content: system},
          %{role: "user", content: user}
        ]
      },
      receive_timeout: 120_000
    )
    |> case do
      {:ok, %{status: 200, body: %{"message" => %{"content" => content}}}} ->
        {:ok, content || "{}"}

      {:ok, %{status: status, body: body}} ->
        {:error, {:api_error, status, body}}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp parse_json(text) do
    text
    |> strip_fences()
    |> Jason.decode()
    |> case do
      {:ok, map} when is_map(map) -> {:ok, map}
      _ -> {:error, :invalid_json}
    end
  end

  defp strip_fences(text) do
    text
    |> String.trim()
    |> String.replace(~r/^```(?:json)?\s*/u, "")
    |> String.replace(~r/\s*```$/u, "")
    |> String.trim()
  end

  def tier1_model do
    case Config.tier1_model() do
      nil ->
        cond do
          ollama_reachable?() -> "ollama/llama3.2"
          Config.openai_api_key() != "" -> "gpt-4o-mini"
          Config.xai_api_key() != "" -> "xai/" <> Config.xai_model()
          Config.anthropic_api_key() != "" -> "anthropic/claude-3-5-haiku-20241022"
          true -> "mock"
        end

      model ->
        model
    end
  end

  def tier2_model do
    case Config.tier2_model() do
      nil ->
        case provider() do
          "xai" -> "xai/" <> Config.xai_model()
          "openai" -> "gpt-4o"
          "anthropic" -> "anthropic/claude-3-5-sonnet-20241022"
          _ -> "mock"
        end

      model ->
        model
    end
  end

  defp ollama_reachable? do
    base = String.trim_trailing(Config.ollama_api_base(), "/")

    case Req.get(base <> "/api/tags", receive_timeout: 1_500) do
      {:ok, %{status: 200}} -> true
      _ -> false
    end
  end

  defp xai_base, do: "https://api.x.ai/v1"
  defp openai_base, do: "https://api.openai.com/v1"
end
