defmodule TalesForge.Game.PerceptionTest do
  use TalesForge.DataCase, async: false

  alias TalesForge.Game.Context
  alias TalesForge.GameSessions
  alias TalesForge.Jido

  setup do
    on_exit(fn ->
      for {id, _pid} <- Jido.list_agents(), do: Jido.stop_agent(id)
    end)

    :ok
  end

  test "Crossroads GM prompt keeps Marta focus and stock, drops initiative internals" do
    {:ok, session} = GameSessions.create_session(%{name: "Perception Crossroads"})
    prompt = Context.format_gm_prompt(Context.build_gm_context(session))

    assert prompt =~ "Marta"
    assert prompt =~ "missing ledger"
    assert prompt =~ "ale" or prompt =~ "Mug of Ale"
    refute prompt =~ "initiative_emitted"
    refute prompt =~ "concern_wait_ticks"
    refute prompt =~ "runtime_state"
  end
end
