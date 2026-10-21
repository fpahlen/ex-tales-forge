defmodule TalesForge.Locations.Cell do
  @moduledoc "One grid cell: the legend item it holds (docs/design-locations.md §3)."

  alias TalesForge.Locations.Legend

  defstruct item: nil, char: nil, blocks: false, opaque: false, link: nil, child: nil

  @type t :: %__MODULE__{
          item: String.t(),
          char: String.t(),
          blocks: boolean(),
          opaque: boolean(),
          link: %{dz: integer()} | nil,
          child: String.t() | nil
        }

  @doc "The cell for `char` in `legend`."
  @spec new(String.t(), Legend.t()) :: t()
  def new(char, %Legend{} = legend) do
    entry = Map.fetch!(legend.items, char)

    %__MODULE__{
      item: entry.item,
      char: char,
      blocks: entry.blocks,
      opaque: entry.opaque,
      link: entry.link
    }
  end
end
