defmodule TalesForge.GitEvents do
  @moduledoc """
  GitHub events on PubSub. The webhook endpoint
  (`TalesForgeWeb.GitHubWebhookController`) checks each delivery
  (`TalesForge.GitEvents.Signature`), maps it to a
  `TalesForge.GitEvents.GitEvent` (`TalesForge.GitEvents.Mapper`) and
  broadcasts `{:git_event, event}` on the topic `"github"`.

  Subscribers: the live PR feed (`TalesForge.PrFeed.Poller`) and the board
  (`TalesForge.Board.GitHubEvents`). The secret is the Fly secret
  `GITHUB_WEBHOOK_SECRET` (config `:github_webhook_secret`). Setup:
  `docs/github-webhooks.md`.
  """

  alias TalesForge.GitEvents.GitEvent

  @topic "github"

  @doc "The PubSub topic, `\"#{@topic}\"`."
  @spec topic() :: String.t()
  def topic, do: @topic

  @doc "Subscribes the caller to `{:git_event, event}` messages."
  @spec subscribe() :: :ok | {:error, term()}
  def subscribe, do: Phoenix.PubSub.subscribe(TalesForge.PubSub, @topic)

  @doc "Broadcasts `{:git_event, event}` on the topic."
  @spec broadcast(GitEvent.t()) :: :ok | {:error, term()}
  def broadcast(%GitEvent{} = event),
    do: Phoenix.PubSub.broadcast(TalesForge.PubSub, @topic, {:git_event, event})

  @doc "The webhook secret (`GITHUB_WEBHOOK_SECRET`), or nil when unset or blank."
  @spec secret() :: String.t() | nil
  def secret do
    case Application.get_env(:ex_tales_forge, :github_webhook_secret) do
      value when is_binary(value) -> if String.trim(value) == "", do: nil, else: value
      _ -> nil
    end
  end
end
