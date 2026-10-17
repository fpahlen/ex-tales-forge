defmodule TalesForge.LLM do
  @moduledoc """
  Two-tier LLM client with mock fallback and JSON validation retry.
  """

  require Logger

  alias TalesForge.AICalls
  alias TalesForge.AppRole
  alias TalesForge.Config
  alias TalesForge.LLM.Stream, as: SSE

  alias TalesForge.Game.Schemas.{
    GMStructuredResponse,
    HandlerResult,
    PlayerAction
  }

  @persona_schema %{
    "type" => "object",
    "required" => ["action"],
    "properties" => %{
      "action" => %{"type" => "string"},
      "option_id" => %{"type" => ["string", "null"]}
    }
  }

  @persona_max_tokens 200

  @scorer_schema %{
    "type" => "object",
    "required" => ["scores", "rationale"],
    "properties" => %{
      "scores" => %{
        "type" => "array",
        "items" => %{
          "type" => "object",
          "required" => ["criterion", "score", "evidence"],
          "properties" => %{
            "criterion" => %{"type" => "integer"},
            "score" => %{"type" => ["integer", "null"], "minimum" => 1, "maximum" => 5},
            "evidence" => %{"type" => "string"}
          }
        }
      },
      "rationale" => %{"type" => "string"}
    }
  }

  # Calls that share the session's x-grok-conv-id (see conv_id/1).
  @narration_purposes ~w(scene gm)

  @scorer_max_tokens 800
  @scorer_temperature 0.2

  # Output budget for gm_notes on top of the narration's TIER2_MAX_TOKENS.
  @gm_notes_max_tokens 100

  # No maxLength / maxItems in the schema: with them xAI does not reuse the
  # prompt cache for the request at all (every GM call came back with
  # cached_tokens 128, measured 2026-10-07; the same request without them hit
  # ~9.3k cached tokens). gm_system.txt asks for short bookkeeping and
  # GMStructuredResponse.decode/1 enforces the hard caps in code.

  # Appended (never prepended) on a retry, so the retry re-sends the original
  # messages byte for byte and still hits the prompt cache.
  @retry_correction "Your previous reply was not valid JSON for the required schema. " <>
                      "Reply to the same request again with ONLY the JSON object."

  @doc """
  Strict structured-output schema shared by the scene call and the GM turn
  (xAI `json_schema`, `strict: true`, name `narration`).

  `narrative` is the first property: strict decoding emits keys in schema order,
  so the player-facing text comes first. `Jason.OrderedObject` keeps that order
  on the wire (plain Elixir maps encode keys sorted).

  One schema for both calls on purpose: xAI places `response_format` ahead of
  the messages in its prompt cache, so a different schema on the scene call
  would stop it from warming the cache for GM turn 1. The scene fills
  `narrative` + `location_name`; the GM leaves `location_name` out.

  `variant` `:lean` (the production GM call) has no `location_name` and no
  `gm_notes`. Its schema is different from the scene schema, so on production
  the scene call does not warm the cache for the first GM turn after it.
  """
  @spec narration_schema(gm_variant()) :: map()
  def narration_schema(variant \\ :full) do
    %{
      "type" => "object",
      "required" => ["narrative"],
      "properties" => Jason.OrderedObject.new(narration_properties(variant))
    }
  end

  @typedoc """
  The GM reply variant. `:full` has every narration field (playtest and local).
  `:lean` has no `gm_notes` and no `location_name` (production). The scene call
  always uses `:full`, because the scene owns `location_name`.
  """
  @type gm_variant :: :full | :lean

  @doc """
  The GM reply variant for an app role: `:lean` on production, else `:full`.

      iex> TalesForge.LLM.gm_variant(:production)
      :lean
      iex> TalesForge.LLM.gm_variant(:playtest)
      :full
  """
  @spec gm_variant(AppRole.role()) :: gm_variant()
  def gm_variant(role \\ AppRole.role())
  def gm_variant(:production), do: :lean
  def gm_variant(_role), do: :full

  # The fields come from TalesForge.Prompt.Profile.narration_fields/1, for the
  # GM call of the role that the variant stands for.
  defp narration_properties(variant) do
    ctx = %TalesForge.Prompt.Ctx{call: :gm, role: variant_role(variant)}
    fields = TalesForge.Prompt.Profile.narration_fields(ctx)

    Enum.filter(all_narration_properties(), fn {key, _} -> key in fields end)
  end

  defp variant_role(:lean), do: :production
  defp variant_role(:full), do: :playtest

  defp all_narration_properties do
    [
      {"narrative", %{"type" => "string"}},
      {"location_name", %{"type" => ["string", "null"]}},
      {"npc_memory_updates",
       %{
         "type" => "array",
         "items" => %{
           "type" => "object",
           "required" => ["npc_id", "summary"],
           "properties" => %{
             "npc_id" => %{"type" => "string"},
             "summary" => %{"type" => "string"}
           }
         }
       }},
      {"context_summary", %{"type" => ["string", "null"]}},
      {"gm_notes", %{"type" => ["string", "null"]}}
    ]
  end

  @typedoc """
  Options for the `complete_*` calls: `:session_id` (conv id and cost rows),
  `:turn_number`. `complete_turn/5` also takes `:on_text` (see there) and
  `:variant` (default `gm_variant/1`).
  """
  @type call_opts :: [
          session_id: String.t() | nil,
          turn_number: integer() | nil,
          on_text: (stream_event() -> any()) | nil,
          variant: gm_variant()
        ]

  @typedoc """
  A streamed narration event. `{:text, narrative}` carries the whole narrative
  so far, so the receiver replaces its text. `:reset` comes before a JSON
  correction retry: the receiver clears the text of the failed reply.
  """
  @type stream_event :: {:text, String.t()} | :reset

  @typedoc "A decoded JSON reply, or why there is none."
  @type result(reply) :: {:ok, reply} | {:error, term()}

  @doc ~s[The configured LLM provider (`LLM_PROVIDER`), e.g. `"xai"` or `"mock"`.]
  @spec provider() :: String.t()
  def provider, do: Config.llm_provider()

  @doc ~s(How a reply was produced, for the stored rows: `"mock"` for the mock model, else `"api"`.)
  @spec llm_source(String.t()) :: String.t()
  def llm_source("mock"), do: "mock"
  def llm_source(_), do: "api"

  @doc "Opening/arrival scene. `messages` come from `Prompts.scene_messages/1`."
  @spec complete_scene([map()], map(), call_opts()) ::
          result(%{location_name: String.t(), narrative: String.t()})
  def complete_scene(messages, intent_context, opts \\ [])
      when is_list(messages) and is_map(intent_context) do
    model = tier2_model()

    if mock?(model) do
      {:ok, mock_scene_response(intent_context)}
    else
      complete_json(model, messages, narration_schema(), Config.tier2_temperature(),
        tier: :scene,
        max_tokens: Config.tier2_max_tokens(),
        session_id: opts[:session_id],
        structured_output: "narration",
        validate: &valid_scene_reply?/1
      )
      |> case do
        {:ok, %{"location_name" => location_name, "narrative" => narrative}}
        when is_binary(location_name) ->
          {:ok, %{location_name: location_name, narrative: narrative}}

        {:ok, map} ->
          {:error, {:invalid_scene, map}}

        error ->
          error
      end
    end
  end

  @doc "A playtest persona's next move (`action`, `option_id`). Persona cost is a bot bucket, not game cost."
  @spec complete_persona(String.t(), String.t(), call_opts()) :: result(map())
  def complete_persona(system, user, opts \\ []) do
    model = tier2_model()

    if mock?(model) do
      {:ok, %{"action" => "I look around and listen.", "option_id" => nil}}
    else
      complete_json(
        model,
        simple_messages(system, user),
        @persona_schema,
        Config.tier2_temperature(),
        tier: :persona,
        max_tokens: @persona_max_tokens,
        session_id: opts[:session_id],
        turn_number: opts[:turn_number]
      )
    end
  end

  @persona_interview_schema %{
    "type" => "object",
    "required" => ["answers", "top_improvements", "quit_risks"],
    "properties" => %{
      "answers" => %{
        "type" => "array",
        "items" => %{
          "type" => "object",
          "required" => ["q_id", "text"],
          "properties" => %{
            "q_id" => %{"type" => "string"},
            "text" => %{"type" => "string"}
          }
        }
      },
      "top_improvements" => %{"type" => "array", "items" => %{"type" => "string"}},
      "quit_risks" => %{"type" => "array", "items" => %{"type" => "string"}}
    }
  }
  @persona_interview_max_tokens 900

  @doc """
  One persona's focus-group interview (`TalesForge.Playtest.FocusGroup`):
  `answers` (`q_id`, `text`), `top_improvements` and `quit_risks`. Purpose
  `persona_interview`, a bot spend bucket. The mock reply answers the bank
  questions with a fixed text.
  """
  @spec complete_persona_interview(String.t(), String.t(), keyword()) :: result(map())
  def complete_persona_interview(system, user, opts \\ []) do
    model = tier2_model()

    if mock?(model) do
      {:ok, mock_persona_interview()}
    else
      complete_json(
        model,
        simple_messages(system, user),
        @persona_interview_schema,
        Config.tier2_temperature(),
        tier: :persona_interview,
        max_tokens: @persona_interview_max_tokens,
        session_id: opts[:session_id]
      )
    end
  end

  defp mock_persona_interview do
    %{
      "answers" =>
        for(
          q <- TalesForge.Playtest.FocusGroup.Questions.bank(),
          do: %{"q_id" => q.id, "text" => "Mock answer."}
        ),
      "top_improvements" => ["Mock: more danger in the first turns."],
      "quit_risks" => []
    }
  end

  @fact_extract_schema %{
    "type" => "object",
    "required" => ["facts"],
    "properties" => %{
      "facts" => %{
        "type" => "array",
        "items" => %{
          "type" => "object",
          "required" => ["about", "kind", "text"],
          "properties" => %{
            "about" => %{"type" => "string"},
            "kind" => %{"type" => "string"},
            "text" => %{"type" => "string"}
          }
        }
      }
    }
  }
  @fact_extract_max_tokens 200

  @doc """
  World agents round 2: new facts and promises read from a finished GM
  narration (`TalesForge.World.Extract`). Purpose `fact_extract`, conv id
  `<session>:facts`, temperature 0.
  """
  @spec complete_fact_extract(String.t(), String.t(), call_opts()) :: result(map())
  def complete_fact_extract(system, user, opts \\ []) do
    model = tier1_model()

    if mock?(model) do
      {:ok, %{"facts" => []}}
    else
      complete_json(model, simple_messages(system, user), @fact_extract_schema, 0.0,
        tier: :fact_extract,
        max_tokens: @fact_extract_max_tokens,
        session_id: opts[:session_id],
        turn_number: opts[:turn_number]
      )
    end
  end

  @doc "The LLM judge's scorecard for a playtest (`scores`, `rationale`); `:criteria` sizes the mock reply."
  @spec complete_scorer(String.t(), String.t(), keyword()) :: result(map())
  def complete_scorer(system, user, opts \\ []) do
    model = tier2_model()

    if mock?(model) do
      {:ok, mock_scorecard(Keyword.get(opts, :criteria, 0))}
    else
      complete_json(model, simple_messages(system, user), @scorer_schema, @scorer_temperature,
        tier: :scorer,
        max_tokens: @scorer_max_tokens,
        session_id: opts[:session_id]
      )
    end
  end

  defp mock_scorecard(criteria) do
    %{
      "scores" =>
        for(n <- 1..criteria//1, do: %{"criterion" => n, "score" => nil, "evidence" => "mock"}),
      "rationale" => "Mock judge: nothing was scored."
    }
  end

  @label_schema %{
    "type" => "object",
    "required" => ["value", "confidence"],
    "properties" => %{
      "value" => %{"type" => "string"},
      "confidence" => %{"type" => "number"}
    }
  }
  @character_text_schema %{
    "type" => "object",
    "required" => [
      "name",
      "race",
      "class",
      "occupation",
      "stats",
      "stats_confidence",
      "skills",
      "skills_confidence",
      "questions"
    ],
    "properties" => %{
      "name" => @label_schema,
      "race" => @label_schema,
      "class" => @label_schema,
      "occupation" => @label_schema,
      "stats" => %{
        "type" => "array",
        "items" => %{
          "type" => "object",
          "required" => ["stat", "value"],
          "properties" => %{"stat" => %{"type" => "string"}, "value" => %{"type" => "integer"}}
        }
      },
      "stats_confidence" => %{"type" => "number"},
      "skills" => %{
        "type" => "array",
        "items" => %{
          "type" => "object",
          "required" => ["skill", "level"],
          "properties" => %{"skill" => %{"type" => "string"}, "level" => %{"type" => "integer"}}
        }
      },
      "skills_confidence" => %{"type" => "number"},
      "questions" => %{"type" => "array", "items" => %{"type" => "string"}}
    }
  }
  @character_text_max_tokens 600

  @doc """
  Character creation from a description (`TalesForge.CharacterCreation.FromText`):
  labels with a confidence (0 to 1) and at most two questions. Purpose
  `character_text`, no session, temperature 0. Each call writes one ai_calls
  row, also the mock call. The mock reply has low confidence for each label.
  """
  @spec complete_character_text(String.t(), String.t(), keyword()) :: result(map())
  def complete_character_text(system, user, _opts \\ []) do
    model = tier1_model()

    if mock?(model) do
      AICalls.record(%{
        purpose: "character_text",
        model: "mock",
        status: "ok",
        latency_ms: 0,
        call_type: "llm",
        conv_id: "tales-forge-character_text"
      })

      {:ok, mock_character_text()}
    else
      complete_json(model, simple_messages(system, user), @character_text_schema, 0.0,
        tier: :character_text,
        max_tokens: @character_text_max_tokens
      )
    end
  end

  defp mock_character_text do
    low = %{"value" => "", "confidence" => 0.0}

    %{
      "name" => low,
      "race" => low,
      "class" => low,
      "occupation" => low,
      "stats" => [],
      "stats_confidence" => 0.0,
      "skills" => [],
      "skills_confidence" => 0.0,
      "questions" => []
    }
  end

  @thought_schema %{
    "type" => "object",
    "required" => ["thought"],
    "properties" => %{"thought" => %{"type" => "string"}}
  }
  @thought_max_tokens 120

  @doc """
  The player character's thought (board card 845b6b15,
  `TalesForge.Characters.Thought`): one or two sentences of inner voice,
  typed as `%{"thought" => text}`. Purpose `thought`, conv id
  `<session>:thought`, temperature 0.7. Each call writes one ai_calls row,
  also the mock call.
  """
  @spec complete_thought(String.t(), String.t(), call_opts()) :: result(map())
  def complete_thought(system, user, opts \\ []) do
    model = tier1_model()

    if mock?(model) do
      AICalls.record(%{
        purpose: "thought",
        model: "mock",
        status: "ok",
        latency_ms: 0,
        call_type: "llm",
        game_session_id: opts[:session_id],
        conv_id: "tales-forge-thought"
      })

      {:ok, %{"thought" => "Something about this stays with me, warm and a little uneasy."}}
    else
      complete_json(model, simple_messages(system, user), @thought_schema, 0.7,
        tier: :thought,
        max_tokens: @thought_max_tokens,
        session_id: opts[:session_id],
        turn_number: opts[:turn_number]
      )
    end
  end

  @board_similar_schema %{
    "type" => "object",
    "required" => ["title", "matches"],
    "properties" => %{
      "title" => %{"type" => "string"},
      "matches" => %{
        "type" => "array",
        "items" => %{
          "type" => "object",
          "required" => ["ref", "reason"],
          "properties" => %{
            "ref" => %{"type" => "string"},
            "reason" => %{"type" => "string"}
          }
        }
      }
    }
  }
  @board_similar_max_tokens 400

  @doc """
  The idea board's similar-card check (`TalesForge.Board.Similar`): a short
  `title` for the new idea and the `matches` (`ref`, `reason`) among the
  cards in the prompt. Purpose `board_similar`, no session, temperature 0.
  The mock reply has no matches and an empty title.
  """
  @spec complete_board_similar(String.t(), String.t(), keyword()) :: result(map())
  def complete_board_similar(system, user, _opts \\ []) do
    model = tier1_model()

    if mock?(model) do
      {:ok, %{"title" => "", "matches" => []}}
    else
      complete_json(model, simple_messages(system, user), @board_similar_schema, 0.0,
        tier: :board_similar,
        max_tokens: @board_similar_max_tokens
      )
    end
  end

  @doc """
  GM turn. `messages` come from `Prompts.gm_messages/3`. The reply is decoded
  into a `GMStructuredResponse`.

  The call streams (`stream: true`). With `:on_text`, the function gets
  `{:text, narrative_so_far}` while the reply arrives, at most once in each
  `:llm_stream_throttle_ms` (default 75), and once more at the end. The
  structured fields are parsed when the reply is complete.

  `:variant` picks the prompt and schema (`gm_variant/1`, by app role).
  """
  @spec complete_turn([map()], PlayerAction.t(), HandlerResult.t(), integer(), call_opts()) ::
          result(GMStructuredResponse.t())
  def complete_turn(
        messages,
        %PlayerAction{} = player_action,
        %HandlerResult{} = handler,
        turn_number,
        opts \\ []
      )
      when is_list(messages) do
    model = tier2_model()
    variant = Keyword.get_lazy(opts, :variant, &gm_variant/0)

    if mock?(model) do
      {:ok, mock_turn_response(player_action, handler, turn_number)}
    else
      complete_json(
        model,
        messages,
        narration_schema(variant),
        Config.tier2_temperature(),
        tier: :tier2,
        max_tokens: Config.tier2_max_tokens() + notes_budget(variant),
        session_id: opts[:session_id],
        turn_number: turn_number,
        structured_output: "narration",
        validate: &valid_gm_reply?/1,
        stream: true,
        on_text: opts[:on_text],
        variant: variant
      )
      |> case do
        {:ok, map} -> {:ok, GMStructuredResponse.decode(map)}
        error -> error
      end
    end
  end

  defp notes_budget(:full), do: @gm_notes_max_tokens
  defp notes_budget(:lean), do: 0

  defp valid_gm_reply?(%{"narrative" => narrative}) when is_binary(narrative),
    do: String.trim(narrative) != ""

  defp valid_gm_reply?(_map), do: false

  defp valid_scene_reply?(%{"location_name" => name} = map) when is_binary(name),
    do: String.trim(name) != "" and valid_gm_reply?(map)

  defp valid_scene_reply?(_map), do: false

  defp mock_scene_response(context) do
    location_name = Map.get(context, "location_name", "Unknown")
    blurb = Map.get(context, "location_blurb", "")
    situation = Map.get(context, "situation_lines", []) |> Enum.join("\n")

    narrative =
      [
        blurb,
        situation,
        "\n_Mock GM: set XAI_API_KEY for full scene narration._"
      ]
      |> Enum.reject(&(is_nil(&1) or &1 == ""))
      |> Enum.join("\n\n")

    %{location_name: location_name, narrative: narrative}
  end

  defp mock_turn_response(
         %PlayerAction{} = player_action,
         %HandlerResult{} = _handler,
         turn_number
       ) do
    narrative =
      "**Turn #{turn_number}** — The world reacts to your action.\n\n" <>
        "#{player_action.overall_intent}\n\n" <>
        "_Mock GM: set XAI_API_KEY for full LLM narration._"

    %GMStructuredResponse{narrative: narrative, raw: %{"narrative" => narrative}}
  end

  # Calls with :structured_output (a schema name) use xAI strict json_schema; the
  # schema travels in response_format, not in the prompt. Other calls, and other
  # providers, keep json_object with the schema pasted at the end of the user text.
  #
  # One retry on unparseable JSON or a reply that fails :validate. The retry
  # re-sends the identical messages with a short correction APPENDED, so the
  # cached prefix (system + rules + state) still matches.
  defp complete_json(model, messages, schema, temperature, opts) do
    {messages, opts} = prepare_schema(model, messages, schema, opts)
    validate = Keyword.get(opts, :validate, fn _map -> true end)

    case dispatch_json(model, messages, temperature, opts, validate) do
      {:error, reason} when reason in [:invalid_json, :invalid_reply] ->
        # The streamed text of the failed reply goes away; the retry streams anew.
        if is_function(opts[:on_text], 1), do: opts[:on_text].(:reset)
        dispatch_json(model, retry_messages(messages), temperature, opts, validate)

      result ->
        result
    end
  end

  defp simple_messages(system, user),
    do: [%{role: "system", content: system}, %{role: "user", content: user}]

  @doc false
  @spec retry_messages([map()]) :: [map()]
  def retry_messages(messages), do: messages ++ [%{role: "user", content: @retry_correction}]

  defp prepare_schema(model, messages, schema, opts) do
    case Keyword.get(opts, :structured_output) do
      name when is_binary(name) ->
        if xai_target?(model) do
          format = %{
            type: "json_schema",
            json_schema: %{name: name, schema: schema, strict: true}
          }

          {messages, Keyword.put(opts, :response_format, format)}
        else
          {paste_schema(messages, schema), opts}
        end

      _ ->
        {paste_schema(messages, schema), opts}
    end
  end

  # json_object fallback: the schema goes at the very end of the last message.
  defp paste_schema(messages, schema) do
    {last, rest} = List.pop_at(messages, -1)

    pasted =
      last.content <>
        "\n\nReturn JSON matching this schema:\n" <> Jason.encode!(schema, pretty: true)

    rest ++ [%{last | content: pasted}]
  end

  defp dispatch_json(model, messages, temperature, opts, validate) do
    with {:ok, raw} <- dispatch(model, messages, temperature, opts),
         {:ok, map} <- parse_json(raw) do
      if validate.(map), do: {:ok, map}, else: {:error, :invalid_reply}
    end
  end

  defp xai_target?(model), do: String.starts_with?(model, "xai/") or provider() == "xai"

  defp dispatch("mock", _messages, _temp, _opts), do: {:error, :mock_model}

  defp dispatch(model, messages, temperature, opts) do
    case AICalls.check_spend_caps(opts[:session_id], purpose(Keyword.get(opts, :tier))) do
      :ok -> request(model, messages, temperature, opts)
      {:error, {kind, limit, spent}} -> spend_capped(model, opts, kind, limit, spent)
    end
  end

  defp spend_capped(model, opts, kind, limit, spent) do
    tier = Keyword.get(opts, :tier, :unknown)

    Logger.warning(
      "llm spend cap hit cap=#{kind} limit_usd=#{usd(limit)} spent_usd=#{usd(spent)} session=#{opts[:session_id]} tier=#{tier} model=#{model}"
    )

    record_call(model, tier, opts, :capped, 0, %{started_at: DateTime.utc_now()})
    {:error, {:spend_cap, kind}}
  end

  defp usd(micro_usd), do: :erlang.float_to_binary(micro_usd / 1_000_000, decimals: 4)

  defp request(model, messages, temperature, opts) do
    started_at = DateTime.utc_now()
    started = System.monotonic_time(:millisecond)
    provider = provider()
    tier = Keyword.get(opts, :tier, :unknown)
    max_tokens = Keyword.get(opts, :max_tokens)

    Logger.info(
      "llm call start tier=#{tier} provider=#{provider} model=#{model} temp=#{temperature} max_tokens=#{max_tokens}"
    )

    result =
      cond do
        xai_target?(model) ->
          call_openai_compatible(model, messages, temperature, xai_base(), Config.xai_api_key(),
            max_tokens: max_tokens,
            headers: [{"x-grok-conv-id", conv_id(opts)}],
            response_format: Keyword.get(opts, :response_format),
            stream: Keyword.get(opts, :stream, false),
            on_text: opts[:on_text]
          )

        String.starts_with?(model, "gpt-") or provider == "openai" ->
          call_openai_compatible(
            model,
            messages,
            temperature,
            openai_base(),
            Config.openai_api_key(),
            max_tokens: max_tokens
          )

        String.starts_with?(model, "ollama/") ->
          call_ollama(model, messages, temperature)

        true ->
          {:error, {:unsupported_model, model}}
      end

    elapsed = System.monotonic_time(:millisecond) - started
    conv = if xai_target?(model), do: conv_id(opts)
    record_call(model, tier, opts, result, elapsed, %{started_at: started_at, conv_id: conv})

    case result do
      {:ok, content, usage} ->
        Logger.info(
          "llm call done tier=#{tier} provider=#{provider} model=#{model} duration_ms=#{elapsed} ttft_ms=#{usage[:ttft_ms]} chars=#{String.length(content)}"
        )

        {:ok, content}

      error ->
        error
    end
  end

  defp record_call(model, tier, opts, result, latency_ms, extra) do
    {status, usage} =
      case result do
        {:ok, _content, usage} -> {"ok", usage}
        :capped -> {"capped", %{}}
        _error -> {"error", %{}}
      end

    AICalls.record(%{
      game_session_id: opts[:session_id],
      turn_number: opts[:turn_number],
      purpose: purpose(tier),
      model: model,
      status: status,
      latency_ms: latency_ms,
      usage: usage,
      call_type: "llm",
      started_at: extra[:started_at],
      conv_id: extra[:conv_id],
      ttft_ms: usage[:ttft_ms],
      narration_variant: variant_name(opts[:variant])
    })
  end

  defp variant_name(nil), do: nil
  defp variant_name(variant), do: Atom.to_string(variant)

  defp purpose(:tier1), do: "intent"
  defp purpose(:tier2), do: "gm"
  defp purpose(tier), do: to_string(tier)

  @doc """
  The `x-grok-conv-id` sent with every xAI call.

  xAI keeps its prompt cache per server; requests with the same conversation id
  are routed to the same server. Only the narration calls of a game session
  (scene and GM turns, which share the narrator + rules prefix) use the bare
  session id. Every other call for the session (persona, scorer, intent) gets
  `<session id>:<purpose>`: when a persona call ran on the session id between
  GM turns, the next GM turn reused nothing (cached_tokens 128); with the
  persona on its own id the same sequence reused the narrator + rules prefix
  (measured 2026-10-07).

  A call without a session gets a stable per-purpose id (`tales-forge-<purpose>`)
  rather than none: its prompt still starts with a static prefix worth reusing,
  and the id carries nothing about a player.
  """
  @spec conv_id(keyword()) :: String.t()
  def conv_id(opts) do
    purpose = purpose(Keyword.get(opts, :tier, :unknown))

    case opts[:session_id] do
      id when is_binary(id) and id != "" and purpose in @narration_purposes -> id
      id when is_binary(id) and id != "" and purpose == "fact_extract" -> id <> ":facts"
      id when is_binary(id) and id != "" -> id <> ":" <> purpose
      _ -> "tales-forge-" <> purpose
    end
  end

  defp call_openai_compatible(model, messages, temperature, base_url, api_key, call_opts) do
    if String.trim(api_key) == "" do
      {:error, :missing_api_key}
    else
      clean_model =
        model |> String.replace_prefix("xai/", "") |> String.replace_prefix("openai/", "")

      body =
        %{
          model: clean_model,
          temperature: temperature,
          response_format: call_opts[:response_format] || %{type: "json_object"},
          messages: messages
        }
        |> maybe_put_max_tokens(call_opts[:max_tokens])

      if call_opts[:stream] do
        stream_openai_compatible(base_url, api_key, body, call_opts)
      else
        post_openai_compatible(base_url, api_key, body, call_opts)
      end
    end
  end

  defp post_openai_compatible(base_url, api_key, body, call_opts) do
    Req.post(
      base_url <> "/chat/completions",
      [
        headers:
          [{"authorization", "Bearer " <> api_key}, {"content-type", "application/json"}] ++
            Keyword.get(call_opts, :headers, []),
        json: body,
        receive_timeout: 120_000,
        retry: false
      ] ++ req_options()
    )
    |> case do
      {:ok,
       %{
         status: 200,
         body: %{"choices" => [%{"message" => %{"content" => content}} | _]} = body
       }} ->
        {:ok, content || "{}", AICalls.usage(body)}

      {:ok, %{status: status, body: body}} ->
        {:error, {:api_error, status, body}}

      {:error, reason} ->
        {:error, reason}
    end
  end

  # stream: true. Req hands each chunk to collect_chunk/3; the state lives in
  # the response's private map. A reply that is not an event stream (an error,
  # or a test stub) is read as one JSON body.
  defp stream_openai_compatible(base_url, api_key, body, call_opts) do
    started = System.monotonic_time(:millisecond)
    on_text = call_opts[:on_text]

    body = Map.merge(body, %{stream: true, stream_options: %{include_usage: true}})

    state = %{
      started: started,
      buffer: "",
      raw: [],
      content: [],
      usage: nil,
      ttft_ms: nil,
      sent: nil,
      last_emit: nil,
      on_text: on_text,
      throttle_ms: Application.get_env(:ex_tales_forge, :llm_stream_throttle_ms, 75)
    }

    Req.post(
      base_url <> "/chat/completions",
      [
        headers:
          [{"authorization", "Bearer " <> api_key}, {"content-type", "application/json"}] ++
            Keyword.get(call_opts, :headers, []),
        json: body,
        receive_timeout: 120_000,
        retry: false,
        into: fn {:data, data}, {req, resp} ->
          state = Req.Response.get_private(resp, :llm_stream, state)
          state = collect_chunk(state, data, event_stream?(resp))
          {:cont, {req, Req.Response.put_private(resp, :llm_stream, state)}}
        end
      ] ++ req_options()
    )
    |> case do
      {:ok, %{status: 200} = resp} ->
        state = Req.Response.get_private(resp, :llm_stream, state)
        finish_stream(state, event_stream?(resp))

      {:ok, %{status: status} = resp} ->
        state = Req.Response.get_private(resp, :llm_stream, state)
        {:error, {:api_error, status, raw_body(state)}}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp event_stream?(resp) do
    resp |> Req.Response.get_header("content-type") |> Enum.any?(&(&1 =~ "event-stream"))
  end

  defp collect_chunk(state, data, false), do: %{state | raw: [state.raw, data]}

  defp collect_chunk(state, data, true) do
    {payloads, rest} = SSE.events(state.buffer <> data)
    state = Enum.reduce(payloads, %{state | buffer: rest}, &collect_event/2)
    maybe_emit(state, false)
  end

  defp collect_event(payload, state) do
    case SSE.decode_event(payload) do
      :done ->
        state

      {text, usage} ->
        state = if usage, do: %{state | usage: usage}, else: state

        cond do
          text == "" -> state
          state.ttft_ms -> %{state | content: [state.content, text]}
          true -> %{state | content: [state.content, text], ttft_ms: elapsed_ms(state)}
        end
    end
  end

  defp elapsed_ms(state), do: System.monotonic_time(:millisecond) - state.started

  # Sends the narrative so far when it changed and the throttle time passed
  # (or always, when `final`).
  defp maybe_emit(%{on_text: on_text} = state, final) when is_function(on_text, 1) do
    now = System.monotonic_time(:millisecond)
    due = final or is_nil(state.last_emit) or now - state.last_emit >= state.throttle_ms

    with true <- due,
         text when is_binary(text) and text != "" <-
           state.content |> IO.iodata_to_binary() |> SSE.partial_narrative(),
         true <- text != state.sent do
      on_text.({:text, text})
      %{state | sent: text, last_emit: now}
    else
      _ -> state
    end
  end

  defp maybe_emit(state, _final), do: state

  defp finish_stream(state, true) do
    state = maybe_emit(state, true)
    content = IO.iodata_to_binary(state.content)
    usage = state.usage |> then(&AICalls.usage(%{"usage" => &1 || %{}}))
    {:ok, if(content == "", do: "{}", else: content), Map.put(usage, :ttft_ms, state.ttft_ms)}
  end

  defp finish_stream(state, false) do
    case raw_body(state) do
      %{"choices" => [%{"message" => %{"content" => content}} | _]} = body ->
        content = content || "{}"

        state = %{state | content: [content], ttft_ms: elapsed_ms(state)}
        maybe_emit(state, true)
        {:ok, content, Map.put(AICalls.usage(body), :ttft_ms, state.ttft_ms)}

      body ->
        {:error, {:api_error, 200, body}}
    end
  end

  defp raw_body(state) do
    raw = IO.iodata_to_binary(state.raw)

    case Jason.decode(raw) do
      {:ok, body} -> body
      _ -> raw
    end
  end

  defp call_ollama(model, messages, temperature) do
    clean = String.replace_prefix(model, "ollama/", "")
    base = String.trim_trailing(Config.ollama_api_base(), "/")

    Req.post(
      base <> "/api/chat",
      json: %{
        model: clean,
        stream: false,
        options: %{temperature: temperature},
        messages: messages
      },
      receive_timeout: 120_000,
      retry: false
    )
    |> case do
      {:ok, %{status: 200, body: %{"message" => %{"content" => content}}}} ->
        {:ok, content || "{}", %{}}

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

  @doc "Model for small calls (intent, fact extraction): `TIER1_MODEL`, else the first configured provider, else `\"mock\"`."
  @spec tier1_model() :: String.t()
  def tier1_model, do: resolve_tier_model(Config.tier1_model())

  @doc "Model for narration and bots (scene, GM, persona, scorer): `TIER2_MODEL`, else as `tier1_model/0`."
  @spec tier2_model() :: String.t()
  def tier2_model, do: resolve_tier_model(Config.tier2_model())

  @doc "`XAI_MODEL`, unless it is a reasoning model (too slow for turns); then the default xAI model."
  @spec effective_xai_model() :: String.t()
  def effective_xai_model do
    model = Config.xai_model()

    if reasoning_model?(model) do
      Logger.warning(
        "XAI_MODEL #{model} is a reasoning model; using #{Config.default_xai_model()} for game turns"
      )

      Config.default_xai_model()
    else
      model
    end
  end

  defp resolve_tier_model(nil) do
    cond do
      Config.xai_api_key() != "" -> "xai/" <> effective_xai_model()
      Config.openai_api_key() != "" -> "gpt-4o-mini"
      ollama_reachable?() -> "ollama/llama3.2"
      Config.anthropic_api_key() != "" -> "anthropic/claude-3-5-haiku-20241022"
      true -> "mock"
    end
  end

  defp resolve_tier_model(model), do: model

  defp ollama_reachable? do
    if Config.xai_api_key() != "" do
      false
    else
      base = String.trim_trailing(Config.ollama_api_base(), "/")

      # Probe must not use Req's default retries (1s+2s+4s on connection refused).
      case Req.get(base <> "/api/tags", receive_timeout: 1_500, retry: false) do
        {:ok, %{status: 200}} -> true
        _ -> false
      end
    end
  end

  defp mock?("mock"), do: true
  defp mock?(_model), do: provider() == "mock"

  @doc """
  True for reasoning models.

      iex> TalesForge.LLM.reasoning_model?("grok-4-fast-reasoning")
      true
      iex> TalesForge.LLM.reasoning_model?("grok-4-fast-non-reasoning")
      false
  """
  @spec reasoning_model?(String.t()) :: boolean()
  def reasoning_model?(model) do
    lowered = String.downcase(model)

    String.contains?(lowered, "reasoning") and not String.contains?(lowered, "non-reasoning")
  end

  defp maybe_put_max_tokens(body, nil), do: body
  defp maybe_put_max_tokens(body, max_tokens), do: Map.put(body, :max_tokens, max_tokens)

  # Test hook: config :ex_tales_forge, :llm_req_options, plug: {Req.Test, ...}
  defp req_options, do: Application.get_env(:ex_tales_forge, :llm_req_options, [])

  # Test hook: config :ex_tales_forge, :xai_api_base (the streaming test server).
  defp xai_base, do: Application.get_env(:ex_tales_forge, :xai_api_base, "https://api.x.ai/v1")
  defp openai_base, do: "https://api.openai.com/v1"
end
