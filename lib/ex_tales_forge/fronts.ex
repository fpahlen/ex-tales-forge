defmodule TalesForge.Fronts do
  @moduledoc """
  Ecto persistence for session fronts. Play-loop only — no Ash.

  `seed_session/1` is a no-op for Crossroads (zero fronts). tin_valley copies
  pack JSON into `FrontInstance.definition` and mutable clocks into `runtime_state`.
  """

  import Ecto.Query

  alias TalesForge.Game.Pack
  alias TalesForge.Game.WorldClock
  alias TalesForge.Repo
  alias TalesForge.Schemas.{FrontInstance, GameSession}

  def seed_session(%GameSession{} = session) do
    case Map.get(session.world_state || %{}, "adventure_id") do
      "tin_valley" -> seed_from_pack(session, Pack.load("tin_valley").fronts)
      _ -> :ok
    end
  end

  def seed_session(_), do: :ok

  def list_all(session_id) when is_binary(session_id) do
    FrontInstance
    |> where([f], f.game_session_id == ^session_id)
    |> order_by([f], f.front_id)
    |> Repo.all()
  end

  def list_live(session_id) when is_binary(session_id) do
    FrontInstance
    |> where([f], f.game_session_id == ^session_id and f.status == "live")
    |> order_by([f], f.front_id)
    |> Repo.all()
  end

  def get_instance(session_id, front_id)
      when is_binary(session_id) and is_binary(front_id) do
    Repo.get_by(FrontInstance, game_session_id: session_id, front_id: front_id)
  end

  defp seed_from_pack(%GameSession{id: session_id, world_state: world}, fronts) do
    world_tick = Map.get(world, "world_tick", WorldClock.default_start_tick())

    Enum.each(fronts, fn defn ->
      front_id = defn["id"]

      runtime = %{
        "clocks" => defn["clocks"] || %{},
        "resources" => defn["resources"] || %{},
        "beliefs" => defn["beliefs"] || %{},
        "memories" => [],
        "public_facts" => defn["public_facts"] || [],
        "since_tick" => world_tick
      }

      %FrontInstance{}
      |> FrontInstance.changeset(%{
        game_session_id: session_id,
        front_id: front_id,
        status: defn["status"] || "live",
        definition: defn,
        runtime_state: runtime
      })
      |> Repo.insert!(
        on_conflict: :nothing,
        conflict_target: [:game_session_id, :front_id]
      )
    end)

    :ok
  end
end
