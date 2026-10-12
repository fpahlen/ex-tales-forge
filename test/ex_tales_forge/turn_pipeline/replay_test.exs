defmodule TalesForge.TurnPipeline.ReplayTest do
  # Replays each turn pipeline fixture. The harness does not exist yet, so
  # every test has the :pending tag. CI excludes the tag (test_helper.exs).
  # Run them with `mix test --include pending`. The spec is in
  # test/fixtures/turn_pipeline/README.md.
  use ExUnit.Case, async: true

  @path "test/fixtures/turn_pipeline/items.jsonl"
  @items @path
         |> File.read!()
         |> String.split("\n", trim: true)
         |> Enum.map(&Jason.decode!/1)

  # The harness module is found at run time, so the compiler does not warn
  # while the module is missing.
  @harness "Elixir.TalesForge.TurnPipeline.Replay"

  for item <- @items do
    @item item
    @tag :pending
    @tag pending_on: item["pending_on"]
    test "#{item["id"]} #{item["category"]}: #{item["description"]}" do
      harness = load_harness(@harness)

      assert harness.run(@item) == :ok
    end
  end

  defp load_harness(name) do
    module = String.to_existing_atom(name)
    if Code.ensure_loaded?(module), do: module, else: missing(name)
  rescue
    ArgumentError -> missing(name)
  end

  defp missing(name) do
    flunk("#{name} is missing. See test/fixtures/turn_pipeline/README.md.")
  end
end
