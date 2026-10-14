defmodule TalesForge.PrFeed.WhatWeDidLLM do
  @moduledoc """
  The model call of the "What have we done" panel
  (`TalesForge.PrFeed.WhatWeDid`). It sends one chat completion to xAI and
  asks for a JSON answer with the key `bullets`.

  - Key: the config `:ex_tales_forge, :xai_api_key`, else XAI_API_KEY. No key
    gives `{:error, :no_key}`, so the panel shows the plain titles.
  - Model: XAI_MODEL, else `#{inspect("grok-4.20-0309-non-reasoning")}` (the
    non-reasoning model that the other small calls use).
  - Temperature 0.2, at most 600 output tokens, 30 s timeout, no retries.
  """

  @url "https://api.x.ai/v1/chat/completions"
  @default_model "grok-4.20-0309-non-reasoning"
  @max_tokens 600

  @schema %{
    "type" => "object",
    "required" => ["bullets"],
    "additionalProperties" => false,
    "properties" => %{
      "bullets" => %{
        "type" => "array",
        "items" => %{
          "type" => "object",
          "required" => ["text", "prs"],
          "additionalProperties" => false,
          "properties" => %{
            "text" => %{"type" => "string"},
            "prs" => %{"type" => "array", "items" => %{"type" => "integer"}}
          }
        }
      }
    }
  }

  @doc "Makes the bullets. Same contract as the `:what_we_did_llm` function."
  @spec complete(String.t(), String.t(), keyword()) :: {:ok, map()} | {:error, term()}
  def complete(system, user, _opts \\ []) do
    case key() do
      nil -> {:error, :no_key}
      key -> request(key, system, user)
    end
  end

  defp request(key, system, user) do
    body = %{
      model: System.get_env("XAI_MODEL", @default_model),
      temperature: 0.2,
      max_tokens: @max_tokens,
      messages: [%{role: "system", content: system}, %{role: "user", content: user}],
      response_format: %{
        type: "json_schema",
        json_schema: %{name: "what_we_did", schema: @schema, strict: true}
      }
    }

    opts =
      [url: @url, json: body, auth: {:bearer, key}, receive_timeout: 30_000, retry: false] ++
        Application.get_env(:ex_tales_forge, :what_we_did_req_options, [])

    with {:ok, %Req.Response{status: 200, body: %{"choices" => [choice | _]}}} <- Req.post(opts),
         text when is_binary(text) <- get_in(choice, ["message", "content"]),
         {:ok, %{} = map} <- Jason.decode(text) do
      {:ok, map}
    else
      {:ok, %Req.Response{status: status}} -> {:error, {:http, status}}
      {:error, reason} -> {:error, reason}
      _other -> {:error, :invalid_reply}
    end
  end

  defp key do
    [Application.get_env(:ex_tales_forge, :xai_api_key), System.get_env("XAI_API_KEY")]
    |> Enum.find(&(is_binary(&1) and String.trim(&1) != ""))
  end
end
