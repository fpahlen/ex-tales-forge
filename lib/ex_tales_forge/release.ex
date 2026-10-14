defmodule TalesForge.Release do
  @moduledoc """
  Used for executing DB release tasks when run in production without Mix
  installed.

  `migrate/0` runs the migrations of each repo in `:ecto_repos`, in order:
  first `TalesForge.Repo` (`priv/repo/migrations`), then
  `TalesForge.Workflow.Repo` (`priv/workflow_repo/migrations`).
  """
  @app :ex_tales_forge

  def migrate do
    load_app()

    for repo <- repos() do
      {:ok, _, _} = Ecto.Migrator.with_repo(repo, &Ecto.Migrator.run(&1, :up, all: true))
    end
  end

  def rollback(repo, version) do
    load_app()
    {:ok, _, _} = Ecto.Migrator.with_repo(repo, &Ecto.Migrator.run(&1, :down, to: version))
  end

  defp repos do
    Application.fetch_env!(@app, :ecto_repos)
  end

  defp load_app do
    Application.load(@app)
  end
end
