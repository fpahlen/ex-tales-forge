defmodule TalesForge.Repo do
  use Ecto.Repo,
    otp_app: :ex_tales_forge,
    adapter: Ecto.Adapters.Postgres
end
