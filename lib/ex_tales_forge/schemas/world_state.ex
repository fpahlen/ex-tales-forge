defmodule TalesForge.Schemas.WorldState do
  @moduledoc """
  The Ecto type of `game_sessions.world_state`: a map, stored without the
  player character (refactor step 10b-2). The character's `characters` row
  is its only stored copy (`TalesForge.Characters.write_multi/1`), so
  `dump/1` leaves `"character"` out and nothing else.

  In memory a session's world still carries `"character"`: a loaded session
  gets it from the row (`TalesForge.Characters.put_sheet/1`), and the turn
  and every reader of the sheet work on that map as before. A struct that
  `Repo.insert/1` or `Repo.update/1` returns keeps it too, so the writes
  after a session save (the characters step of the turn Multi, the seed at
  session create) read the sheet that was just played.

  A session stored before 10b-2 still has `"character"` in its column until
  its next save. `load/1` keeps it, and `TalesForge.Characters.put_sheet/1`
  reads it before the row; the next turn writes it to the row.
  """

  use Ecto.Type

  @impl true
  def type, do: :map

  @impl true
  def cast(value), do: Ecto.Type.cast(:map, value)

  @impl true
  def load(value), do: Ecto.Type.load(:map, value)

  @impl true
  def dump(%{} = world), do: Ecto.Type.dump(:map, Map.delete(world, "character"))
  def dump(value), do: Ecto.Type.dump(:map, value)
end
