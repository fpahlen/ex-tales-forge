# Unit tests never call a live LLM. A developer shell with XAI_API_KEY
# would otherwise make every turn POST to api.x.ai (and retry on failure).
System.put_env("LLM_PROVIDER", "mock")

# Tests with the :pending tag wait for code that is not on main yet (for
# example the turn pipeline replay fixtures). Run them with
# `mix test --include pending`.
ExUnit.start(exclude: [:pending])
Ecto.Adapters.SQL.Sandbox.mode(TalesForge.Repo, :manual)
Ecto.Adapters.SQL.Sandbox.mode(TalesForge.Workflow.Repo, :manual)
