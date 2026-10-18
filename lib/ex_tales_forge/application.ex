defmodule TalesForge.Application do
  # See https://elixir.hexdocs.pm/Application.html
  # for more information on OTP Applications
  @moduledoc false

  use Application

  @impl true
  def start(_type, _args) do
    children = [
      TalesForgeWeb.Telemetry,
      TalesForge.Repo,
      # Before Oban, so they stop after it: a turn job still running in its
      # shutdown grace period keeps its World.Instance and Task.
      {Registry, keys: :unique, name: TalesForge.World.Registry},
      {DynamicSupervisor, name: TalesForge.World.Supervisor, strategy: :one_for_one},
      {Task.Supervisor, name: TalesForge.World.TaskSupervisor},
      {Oban, Application.fetch_env!(:ex_tales_forge, Oban)},
      {DNSCluster, query: Application.get_env(:ex_tales_forge, :dns_cluster_query) || :ignore},
      {Phoenix.PubSub, name: TalesForge.PubSub},
      TalesForge.Presence,
      TalesForge.Online.Peer,
      {Task.Supervisor, name: TalesForge.Playtest.Supervisor},
      {Task.Supervisor, name: TalesForge.Playtest.SeriesSupervisor},
      {Task.Supervisor, name: TalesForge.IntentJev.Supervisor},
      TalesForge.AdminAuth.MembershipCache,
      TalesForge.Survey.Cache,
      TalesForgeWeb.Endpoint,
      # Playtest only: the hourly code heat map sample (TalesForge.CodeHeat).
      TalesForge.CodeHeat.Sampler
    ]

    # See https://elixir.hexdocs.pm/Supervisor.html
    # for other strategies and supported options
    opts = [strategy: :one_for_one, name: TalesForge.Supervisor]
    Supervisor.start_link(children, opts)
  end

  # Tell Phoenix to update the endpoint configuration
  # whenever the application is updated.
  @impl true
  def config_change(changed, _new, removed) do
    TalesForgeWeb.Endpoint.config_change(changed, removed)
    :ok
  end
end
