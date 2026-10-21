defmodule TalesForge.Canon.SessionSnapshot do
  @moduledoc """
  The session side of the review: the places, the NPC ids and the stored
  `world_fact` events of one game session, as plain data.

  `from_session/1` reads the database. `TalesForge.Canon.Diff` uses the
  struct and does no reads.
  """
  alias TalesForge.GameCharacter.Rows

  alias TalesForge.Schemas.GameSession
  alias TalesForge.World

  @type t :: %__MODULE__{
          session_id: String.t() | nil,
          adventure_id: String.t() | nil,
          places: %{String.t() => map()},
          npc_ids: [String.t()],
          npc_names: %{String.t() => String.t()},
          facts: %{String.t() => [map()]}
        }

  defstruct session_id: nil,
            adventure_id: nil,
            places: %{},
            npc_ids: [],
            npc_names: %{},
            facts: %{}

  @doc "Reads one session from the database."
  @spec from_session(GameSession.t()) :: t()
  def from_session(%GameSession{} = session) do
    world = session.world_state || %{}
    instances = Rows.list(session.id)

    names =
      Map.new(instances, fn inst ->
        {inst.npc_id, get_in(inst.personality, ["name"]) || inst.npc_id}
      end)

    %__MODULE__{
      session_id: session.id,
      adventure_id: world["adventure_id"],
      places: world["locations"] || %{},
      npc_ids:
        (Map.keys(names) ++ List.wrap(world["present_npcs"])) |> Enum.uniq() |> Enum.sort(),
      npc_names: names,
      facts: World.stored_facts(session.id)
    }
  end
end
