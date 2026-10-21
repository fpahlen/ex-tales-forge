defmodule TalesForge.Prompt.Sections.Surroundings do
  @moduledoc """
  What the character sees around it, from the location grid
  (`data[:surroundings]`, `TalesForge.Locations.Prompt`). Only with
  `LOCATION_GRID=on` (`TalesForge.Prompt.Profile`).

      iex> TalesForge.Prompt.Sections.Surroundings.text(nil)
      nil
  """
  use TalesForge.Prompt.Section, id: :surroundings, slot: :turn

  @impl true
  def render(ctx), do: text(Map.get(ctx.data, :surroundings))

  @doc "The GM note for the surroundings lines, or nil when there are none."
  @spec text(String.t() | nil) :: String.t() | nil
  def text(lines) when is_binary(lines) and lines != "" do
    """
    ## Around the character (from the map)
    Where things are, relative to the way the character faces, in metres. Narrate from it; don't move or invent fixtures.
    #{lines}
    """
  end

  def text(_lines), do: nil
end
