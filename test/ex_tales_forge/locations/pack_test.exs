defmodule TalesForge.Locations.PackTest do
  use ExUnit.Case, async: true

  alias TalesForge.Locations.Pack

  test "Tin Valley has the Valley Inn ground floor" do
    grids = Pack.grids("tin_valley")
    assert [%{id: "valley_inn", z: 0, scale: "room"}] = grids["valley_inn"]
    assert Pack.grid(grids, "valley_inn", 0).cells[{9, 0, 0}].item == "main door"
    assert Pack.grid(grids, "valley_inn", 1) == nil
    assert Map.has_key?(TalesForge.Game.Pack.load("tin_valley").locations, "valley_inn")
  end

  @tag :tmp_dir
  test "a pack with no grids has none", %{tmp_dir: dir} do
    assert Pack.grids_in(dir) == %{}
  end

  @tag :tmp_dir
  test "a badly named grid file raises", %{tmp_dir: dir} do
    File.mkdir_p!(Path.join(dir, "grids/room"))
    File.write!(Path.join(dir, "grids/room/inn.txt"), "")
    assert_raise ArgumentError, ~r/_z<z>/, fn -> Pack.grids_in(dir) end
  end
end
