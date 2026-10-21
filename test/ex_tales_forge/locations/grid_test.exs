defmodule TalesForge.Locations.GridTest do
  use ExUnit.Case, async: true

  alias TalesForge.Locations.Grid
  alias TalesForge.Locations.Legend

  doctest TalesForge.Locations.Grid
  doctest TalesForge.Locations.Legend

  @world Path.join(:code.priv_dir(:ex_tales_forge), "adventures/tin_valley/world")

  defp legend do
    {:ok, legend} =
      @world
      |> Path.join("legends/room.json")
      |> File.read!()
      |> Jason.decode!()
      |> Legend.parse()

    legend
  end

  defp inn, do: File.read!(Path.join(@world, "grids/room/valley_inn_z0.txt"))

  test "the Valley Inn ground floor parses into 400 cells" do
    assert {:ok, grid} = Grid.parse(inn(), legend(), %{id: "valley_inn", z: 0})
    assert map_size(grid.cells) == 400
    assert grid.scale == "room" and grid.cell_m == 1
    assert Grid.find(grid, "main door") == [{9, 0, 0}]
    assert Grid.find(grid, "kitchen back door") == [{9, 19, 0}]
    assert Grid.find(grid, "stairs up") == [{14, 1, 0}]
    assert Grid.at(grid, {14, 1, 0}).link == %{dz: 1}
    assert length(Grid.find(grid, "open hearth")) == 12
  end

  test "blocks and opaque are separate: a window blocks walking, not sight" do
    {:ok, legend} =
      Legend.parse(%{
        "scale" => "room",
        "items" => %{"o" => %{"item" => "window", "blocks" => true}}
      })

    assert %{blocks: true, opaque: false} = legend.items["o"]
    assert legend().items["#"].opaque and legend().items["#"].blocks
    refute legend().items["C"].blocks
  end

  test "an unknown character and a short row are errors" do
    bad = String.replace(inn(), "S", "?", global: false)
    assert {:error, {:unknown_char, "?", {14, 1}}} = Grid.parse(bad, legend(), %{id: "x", z: 0})

    short =
      inn()
      |> String.split("\n")
      |> List.update_at(3, &String.slice(&1, 0, 19))
      |> Enum.join("\n")

    assert {:error, :not_20x20} = Grid.parse(short, legend(), %{id: "x", z: 0})
  end

  test "a bad legend is an error" do
    assert {:error, :bad_legend} = Legend.parse(%{"items" => %{}})

    assert {:error, :bad_item} =
             Legend.parse(%{"scale" => "room", "items" => %{"ab" => %{"item" => "x"}}})
  end
end
