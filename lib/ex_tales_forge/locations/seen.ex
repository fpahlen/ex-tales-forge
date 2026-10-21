defmodule TalesForge.Locations.Seen do
  @moduledoc "One item a character sees, which way and how far (`TalesForge.Locations.Surroundings`)."

  defstruct item: nil, dir: nil, distance_m: 0.0, cell: nil

  @type dir :: :ahead | :right | :behind | :left
  @type t :: %__MODULE__{
          item: String.t(),
          dir: dir(),
          distance_m: float(),
          cell: TalesForge.Locations.Grid.coord()
        }
end
