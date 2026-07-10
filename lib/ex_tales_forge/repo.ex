defmodule TalesForge.Repo do
  # Upgraded to AshPostgres.Repo for Phase 2 authoring resources.
  # Continues to work as a standard Ecto.Repo for existing runtime schemas.
  use AshPostgres.Repo,
    otp_app: :ex_tales_forge,
    warn_on_missing_ash_functions?: false

  def installed_extensions do
    # Required for full AshPostgres features (atomics, string ops, ||/&&, etc.)
    ["ash-functions", "uuid-ossp"]
  end

  def min_pg_version, do: %Version{major: 16, minor: 0, patch: 0}
end
