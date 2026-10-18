defmodule TalesForge.Schemas.Character.InventoryItem do
  @moduledoc "Embedded: an item a character carries. `price_copper` set means it is for sale (an NPC's stock)."

  use Ecto.Schema
  import Ecto.Changeset

  @primary_key false

  embedded_schema do
    field :id, :string
    field :name, :string
    field :quantity, :integer, default: 1
    field :price_copper, :integer
    # The sheet's own item fields (`TalesForge.Game.Inventory.normalize_items/1`,
    # `Catalogue` equip), so the row round-trips the sheet.
    field :copper_value, :integer
    field :equipped, :boolean
  end

  def changeset(item, attrs) do
    item
    |> cast(attrs, [:id, :name, :quantity, :price_copper, :copper_value, :equipped])
    |> validate_required([:id, :name, :quantity])
    |> validate_number(:quantity, greater_than_or_equal_to: 0)
    |> validate_number(:price_copper, greater_than_or_equal_to: 0)
    |> validate_number(:copper_value, greater_than_or_equal_to: 0)
  end
end
