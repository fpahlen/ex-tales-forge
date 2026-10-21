defmodule TalesForge.Game.Pack.Raw do
  @moduledoc false

  # A pack as read from its files (TalesForge.Game.Pack.load/2), before the
  # checks and before the loaded map is built.
  defstruct adventure_id: nil,
            adventure: %{},
            locations: %{},
            npcs: [],
            player_character: %{},
            fronts: []
end
