defmodule Mix.Tasks.Characters.Backfill do
  @moduledoc """
  Writes or refreshes `characters` rows for every existing session: the
  player character from its row, or from a sheet still stored in
  `world_state["character"]` (a session not saved since step 10b-2), and the
  NPC rows' relationship to it.
  Idempotent and safe to re-run; see `TalesForge.Characters.backfill/0`.

      mix characters.backfill

  On a release, call it over rpc instead:

      bin/ex_tales_forge rpc 'TalesForge.Characters.backfill() |> IO.inspect()'
  """
  use Mix.Task

  @shortdoc "Backfill characters rows for existing sessions"

  @impl Mix.Task
  def run(_args) do
    Mix.Task.run("app.start")
    result = TalesForge.Characters.backfill()
    Mix.shell().info(inspect(result, pretty: true, limit: :infinity))
    if result.failed != [], do: exit({:shutdown, 1})
  end
end
