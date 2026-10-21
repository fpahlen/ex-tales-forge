defmodule TalesForge.Schemas.WorldState do
  @moduledoc """
  The Ecto type of `game_sessions.world_state`: a map, stored without the
  player character (refactor step 10b-2) and without the old copies of the
  GM characters' state, `"npc_state"` and `"npc_moods"` (step 10f PR 4).

  The character's `characters` row is its only stored copy
  (`TalesForge.GameCharacter.Store.write_multi/2`), so `dump/1` leaves `"character"`
  out. In memory a session's world still carries `"character"`: a loaded
  session gets it from the row (`TalesForge.GameCharacter.Store.put_sheet/1`), and
  the turn and every reader of the sheet work on that map as before. A
  struct that `Repo.insert/1` or `Repo.update/1` returns keeps it too, so
  the writes after a session save (the characters step of the turn Multi,
  the seed at session create) read the sheet that was just played.

  A session stored before 10b-2 still has `"character"` in its column until
  its next save. `load/1` keeps it, and `TalesForge.GameCharacter.Store.put_sheet/1`
  reads it before the row; the next turn writes it to the row.

  The NPCs' wounds, the minor foes and the gut reactions are on the GM
  characters' rows (`TalesForge.GameCharacter.Store.cast/1`). A world stored before
  10f PR 4 may still hold `"npc_state"` and `"npc_moods"`: `load/1` drops
  them, so nothing reads them, and `dump/1` never writes them.

  `"positions"` (`TalesForge.Locations.Positions.Json`) is parsed here into
  `%Position{}` structs on load and written back as JSON on dump.
  """

  use Ecto.Type

  alias TalesForge.Locations.Positions.Json

  @retired ~w(npc_state npc_moods)

  @impl true
  def type, do: :map

  @impl true
  def cast(value), do: Ecto.Type.cast(:map, value)

  @impl true
  def load(%{} = world), do: {:ok, world |> Map.drop(@retired) |> Json.parse()}
  def load(_value), do: :error

  @impl true
  def dump(%{} = world),
    do: {:ok, world |> Map.drop(["character" | @retired]) |> Json.json()}

  def dump(_value), do: :error
end
