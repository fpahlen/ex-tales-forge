defmodule TalesForge.Locations.Legend do
  @moduledoc """
  What each character of a grid means at one scale (docs/design-locations.md).

  World-pack data, one file per scale (`world/legends/<scale>.json`), so the
  same character can mean different things at different scales (`S` is
  stairs in a room, sea in a region). `aliases` are the other words a
  player may use for the item ("bar" for the bar desk). `blocks` stops walking, `opaque` stops
  sight; they are separate because a window blocks walking but not sight.
  """

  alias TalesForge.Locations.Legend.Item

  defstruct scale: nil, cell_m: 1, items: %{}

  @type t :: %__MODULE__{scale: String.t(), cell_m: number(), items: %{String.t() => Item.t()}}

  defmodule Item do
    @moduledoc "One legend entry: the item a character stands for."
    defstruct item: nil, blocks: false, opaque: false, link: nil, aliases: []

    @type t :: %__MODULE__{
            item: String.t(),
            blocks: boolean(),
            opaque: boolean(),
            link: %{dz: integer()} | nil,
            aliases: [String.t()]
          }

    @doc "An item from its legend entry."
    @spec new(map()) :: t()
    def new(entry) do
      %__MODULE__{
        item: entry["item"],
        blocks: entry["blocks"] == true,
        opaque: entry["opaque"] == true,
        link: link(entry["link"]),
        aliases: Map.get(entry, "aliases", [])
      }
    end

    defp link(%{"dz" => dz}) when is_integer(dz), do: %{dz: dz}
    defp link(_link), do: nil
  end

  @doc """
  A legend from its decoded JSON.

      iex> {:ok, legend} = TalesForge.Locations.Legend.parse(%{"scale" => "room", "items" => %{"#" => %{"item" => "wall", "blocks" => true}}})
      iex> legend.items["#"].blocks
      true
  """
  @spec parse(map()) :: {:ok, t()} | {:error, term()}
  def parse(%{"scale" => scale, "items" => %{} = items} = data) when is_binary(scale) do
    if Enum.all?(items, &entry?/1) do
      {:ok,
       %__MODULE__{
         scale: scale,
         cell_m: Map.get(data, "cell_m", 1),
         items: Map.new(items, fn {char, entry} -> {char, Item.new(entry)} end)
       }}
    else
      {:error, :bad_item}
    end
  end

  def parse(_data), do: {:error, :bad_legend}

  # One character (a single codepoint) and an item name.
  defp entry?({<<_char::utf8>>, %{"item" => item}}), do: is_binary(item)
  defp entry?(_entry), do: false
end
