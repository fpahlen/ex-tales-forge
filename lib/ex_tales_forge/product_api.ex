defmodule TalesForge.ProductApi do
  @moduledoc """
  The data that the product app gives to Workflow (board card "Workflow
  split 4/5: Product app API"). Workflow gets only this data:

  1. Costs: the AI spend for each Stockholm day of the last 7 days, and the
     Jev intent latency of the last 7 days (`costs/1`).
  2. Online players: the founders online on the product app (`online/0`).
  3. Running commit: the commit of this app (`current`) and the commit that
     each app runs (`running_commits/0`).
  4. Persona scores: the Jev score of each persona over the playtest runs
     on this app (`persona_scores/0`).

  Each function returns a map with string keys, the same as the JSON of
  `GET /internal/product/*` (`TalesForgeWeb.ProductApiController`). The
  Workflow client (`Workflow.ProductApp`) reads the same shape from the
  local adapter and from the HTTP adapter.
  """

  alias TalesForge.Online
  alias TalesForge.Playtest.RunMeta
  alias TalesForge.ProductApi.{Costs, PersonaScores, RunningCommits}

  @doc """
  The bearer token of `GET /internal/product/*` (the secret
  `PRODUCT_APP_API_TOKEN`, config `:product_api`), or nil when unset or blank.
  """
  @spec token() :: String.t() | nil
  def token do
    case Application.get_env(:ex_tales_forge, :product_api, [])[:token] do
      token when is_binary(token) ->
        if String.trim(token) == "", do: nil, else: String.trim(token)

      _ ->
        nil
    end
  end

  @doc "The costs of the last 7 days at `now` (`TalesForge.ProductApi.Costs`)."
  @spec costs(DateTime.t()) :: map()
  def costs(now \\ DateTime.utc_now()) do
    %{"spend" => Costs.spend(now), "intent_latency" => Costs.intent_latency(now)}
  end

  @doc "The founders online."
  @spec online() :: map()
  def online, do: %{"people" => Enum.map(Online.people(), &person/1)}

  @doc "The commit that each app runs (`TalesForge.ProductApi.RunningCommits`)."
  @spec running_commits() :: map()
  def running_commits do
    running = RunningCommits.running()

    %{
      "current" => RunMeta.git_sha(),
      "production" => running.production,
      "playtest" => running.playtest
    }
  end

  @doc "The persona scores (`TalesForge.ProductApi.PersonaScores`); `scores` is nil without data."
  @spec persona_scores() :: map()
  def persona_scores, do: %{"scores" => PersonaScores.scores()}

  defp person(p) do
    %{
      "key" => p.key,
      "email" => p.email,
      "login" => p.login,
      "locations" => p.locations,
      "since" => iso(p.since)
    }
  end

  defp iso(%DateTime{} = at), do: DateTime.to_iso8601(at)
  defp iso(_), do: nil
end
