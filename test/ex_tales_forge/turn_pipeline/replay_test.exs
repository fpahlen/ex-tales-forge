defmodule TalesForge.TurnPipeline.ReplayTest do
  # Replays each turn pipeline fixture with TalesForge.TurnPipeline.Replay
  # (test/support/turn_pipeline/replay.ex). A fixture runs when all its
  # `pending_on` keys have landed on this branch
  # (TalesForge.TurnPipeline.Landed). The other fixtures keep the :pending
  # tag. CI excludes the tag (test_helper.exs). Run them with
  # `mix test --include pending`. The spec is in
  # test/fixtures/turn_pipeline/README.md.
  use TalesForge.DataCase, async: false

  alias TalesForge.Jido
  alias TalesForge.TurnPipeline.{Landed, Replay}

  @path "test/fixtures/turn_pipeline/items.jsonl"
  @external_resource @path
  @items @path
         |> File.read!()
         |> String.split("\n", trim: true)
         |> Enum.map(&Jason.decode!/1)

  setup do
    on_exit(fn ->
      for {id, _pid} <- Jido.list_agents(), do: Jido.stop_agent(id)
      System.put_env("LLM_PROVIDER", "mock")
      System.delete_env("XAI_API_KEY")
    end)

    :ok
  end

  for item <- @items do
    @item item
    unless Landed.active?(item), do: @tag(:pending)
    @tag pending_on: item["pending_on"]
    test "#{item["id"]} #{item["category"]}: #{item["description"]}" do
      assert Replay.run(@item) == :ok
    end
  end
end
