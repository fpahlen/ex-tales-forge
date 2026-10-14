defmodule Workflow.ProductApp do
  @moduledoc """
  The client that Workflow uses to read data from the product app. Workflow
  reads only this data, and never reads product-app tables or modules:

  1. `costs/1`: the AI spend of each day and the intent latency, last 7 days.
  2. `online/0`: the founders online on the product app.
  3. `running_commits/0`: the commit of the product app and of each app.
  4. `persona_scores/0`: the Jev score of each persona over the playtest runs.

  The adapter does the I/O. `Workflow.ProductApp.Local` calls the product app
  in the same release. `Workflow.ProductApp.Http` calls its
  `GET /internal/product/*` routes with a bearer token. The config
  `:ex_tales_forge, Workflow.ProductApp, adapter:` selects the adapter. The
  default is the local adapter. This module only decodes the answers, so
  both adapters give the same result.
  """

  @typedoc "One founder online on the product app."
  @type person :: %{
          key: String.t(),
          email: String.t() | nil,
          login: String.t() | nil,
          locations: [String.t()],
          since: DateTime.t() | nil
        }

  @typedoc "The online data."
  @type online :: %{people: [person()]}

  @typedoc "The costs data. Each part is nil when the product app has no data."
  @type costs :: %{spend: map() | nil, intent_latency: map() | nil}

  @typedoc """
  The commits. `current` is the commit of the product app that this Workflow
  uses. `production` and `playtest` are the commits of each app. Nil when
  unknown.
  """
  @type running :: %{
          current: String.t() | nil,
          production: String.t() | nil,
          playtest: String.t() | nil
        }

  @doc "Reads the costs of the last 7 days at `now`. Returns a map with string keys."
  @callback costs(DateTime.t()) :: {:ok, map()} | :error

  @doc "Reads the online data. Returns a map with string keys."
  @callback online() :: {:ok, map()} | :error

  @doc "Reads the running commits. Returns a map with string keys."
  @callback running_commits() :: {:ok, map()} | :error

  @typedoc "The score of one persona."
  @type persona_score :: %{
          score: float() | nil,
          low_confidence_pct: non_neg_integer() | nil,
          turns: non_neg_integer() | nil
        }

  @typedoc "The persona scores, or nil when the product app has no scored turn."
  @type scores ::
          %{
            since: String.t() | nil,
            runs: non_neg_integer(),
            by_persona: %{String.t() => persona_score()}
          }
          | nil

  @doc "Reads the persona scores. Returns a map with string keys."
  @callback persona_scores() :: {:ok, map()} | :error

  @doc """
  The adapter for `persona_scores/0`: config
  `:ex_tales_forge, Workflow.ProductApp, persona_scores_adapter:`, else
  `adapter/0`. The persona scores can come from another app (playtest runs
  the persona playtests) while the other data stays local.
  """
  @spec scores_adapter() :: module()
  def scores_adapter do
    Application.get_env(:ex_tales_forge, __MODULE__, [])[:persona_scores_adapter] || adapter()
  end

  @doc "The adapter in use."
  @spec adapter() :: module()
  def adapter do
    Application.get_env(:ex_tales_forge, __MODULE__, [])[:adapter] || Workflow.ProductApp.Local
  end

  @doc "The costs of the last 7 days at `now`. Each part is nil when it is not available."
  @spec costs(DateTime.t()) :: costs()
  def costs(now \\ DateTime.utc_now()) do
    case adapter().costs(now) do
      {:ok, body} -> decode_costs(body)
      :error -> %{spend: nil, intent_latency: nil}
    end
  end

  @doc "The online data. Empty when it is not available."
  @spec online() :: online()
  def online do
    case adapter().online() do
      {:ok, body} -> decode_online(body)
      :error -> %{people: []}
    end
  end

  @doc "The commit that each app runs. Nil for each app that is not known."
  @spec running_commits() :: running()
  def running_commits do
    case adapter().running_commits() do
      {:ok, body} -> decode_running(body)
      :error -> %{current: nil, production: nil, playtest: nil}
    end
  end

  @doc "The persona scores. Nil when they are not available."
  @spec persona_scores() :: scores()
  def persona_scores do
    case scores_adapter().persona_scores() do
      {:ok, body} -> decode_scores(body)
      :error -> nil
    end
  end

  @doc """
  Decodes the persona scores answer. A persona with a bad value is left out.

      iex> Workflow.ProductApp.decode_scores(%{"scores" => %{"since" => "2026-10-07", "runs" => 3,
      ...>   "by_persona" => %{"hawk" => %{"score" => 3.5, "low_confidence_pct" => 20, "turns" => 9}, "x" => 1}}})
      %{since: "2026-10-07", runs: 3, by_persona: %{"hawk" => %{score: 3.5, low_confidence_pct: 20, turns: 9}}}
      iex> Workflow.ProductApp.decode_scores(%{"scores" => nil})
      nil
  """
  @spec decode_scores(term()) :: scores()
  def decode_scores(%{"scores" => %{"by_persona" => %{} = by} = s}) when map_size(by) > 0 do
    %{
      since: string(s["since"]),
      runs: if(is_integer(s["runs"]), do: s["runs"], else: 0),
      by_persona: for({p, %{} = v} <- by, is_binary(p), into: %{}, do: {p, persona_score(v)})
    }
  end

  def decode_scores(_body), do: nil

  defp persona_score(v) do
    %{
      score: if(is_number(v["score"]), do: v["score"] * 1.0),
      low_confidence_pct: if(is_integer(v["low_confidence_pct"]), do: v["low_confidence_pct"]),
      turns: if(is_integer(v["turns"]), do: v["turns"])
    }
  end

  @doc """
  Decodes the costs answer.

      iex> Workflow.ProductApp.decode_costs(%{"spend" => %{"total_usd" => 2.0}, "intent_latency" => nil})
      %{spend: %{"total_usd" => 2.0}, intent_latency: nil}
      iex> Workflow.ProductApp.decode_costs("bad")
      %{spend: nil, intent_latency: nil}
  """
  @spec decode_costs(term()) :: costs()
  def decode_costs(%{} = body),
    do: %{spend: map_or_nil(body["spend"]), intent_latency: map_or_nil(body["intent_latency"])}

  def decode_costs(_body), do: %{spend: nil, intent_latency: nil}

  @doc """
  Decodes the online answer.

      iex> Workflow.ProductApp.decode_online(%{"people" => [%{"key" => "ada",
      ...>   "email" => "ada@example.com", "login" => "ada",
      ...>   "locations" => ["Docs on production"], "since" => "2026-10-10T12:00:00Z"}, "bad"]})
      %{people: [%{key: "ada", email: "ada@example.com", login: "ada",
          locations: ["Docs on production"], since: ~U[2026-10-10 12:00:00Z]}]}
  """
  @spec decode_online(term()) :: online()
  def decode_online(%{} = body),
    do: %{people: body |> Map.get("people", []) |> list() |> Enum.flat_map(&person/1)}

  def decode_online(_body), do: %{people: []}

  @doc """
  Decodes the running commits answer. A value that is not a commit sha is nil.

      iex> Workflow.ProductApp.decode_running(%{"current" => "abcdef1", "production" => "ABCDEF1", "playtest" => "<x>"})
      %{current: "abcdef1", production: "abcdef1", playtest: nil}
  """
  @spec decode_running(term()) :: running()
  def decode_running(%{} = body) do
    %{
      current: sha(body["current"]),
      production: sha(body["production"]),
      playtest: sha(body["playtest"])
    }
  end

  def decode_running(_body), do: %{current: nil, production: nil, playtest: nil}

  defp person(%{"key" => key} = p) when is_binary(key) do
    [
      %{
        key: key,
        email: string(p["email"]),
        login: string(p["login"]),
        locations: p |> Map.get("locations", []) |> list() |> Enum.filter(&is_binary/1),
        since: time(p["since"])
      }
    ]
  end

  defp person(_), do: []

  defp time(%DateTime{} = at), do: at

  defp time(at) when is_binary(at) do
    case DateTime.from_iso8601(at) do
      {:ok, at, _} -> at
      _ -> nil
    end
  end

  defp time(_), do: nil

  defp sha(sha) when is_binary(sha) do
    sha = sha |> String.trim() |> String.downcase()
    if Regex.match?(~r/\A[0-9a-f]{7,40}\z/, sha), do: sha
  end

  defp sha(_), do: nil

  defp map_or_nil(%{} = m), do: m
  defp map_or_nil(_), do: nil
  defp list(l) when is_list(l), do: l
  defp list(_), do: []
  defp string(s) when is_binary(s), do: s
  defp string(_), do: nil
end
