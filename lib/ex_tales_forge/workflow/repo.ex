defmodule TalesForge.Workflow.Repo do
  @moduledoc """
  The Ecto repo of Workflow, the team tools (`priv/team/product-boundary.md`).

  Workflow reads and writes its tables only through this repo. The tables are
  in the Postgres schema `workflow`. Each Workflow schema module sets
  `@schema_prefix "workflow"`. The repo uses the same database URL as
  `TalesForge.Repo`, with its own pool. The migrations are in
  `priv/workflow_repo/migrations`.

  Product-app code does not call this repo. `mix deploy.check_boundaries`
  checks this.
  """

  use Ecto.Repo,
    otp_app: :ex_tales_forge,
    adapter: Ecto.Adapters.Postgres

  @doc "The Postgres schema of the Workflow tables."
  @spec prefix() :: String.t()
  def prefix, do: "workflow"
end
