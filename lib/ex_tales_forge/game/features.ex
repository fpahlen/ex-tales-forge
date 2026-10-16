defmodule TalesForge.Game.Features do
  @moduledoc """
  World features of a session, fixed when the session is created and stored
  as `world_state["features"]`. Turning a
  flag on or off changes new sessions only.

  - `"inn_world"` (`INN_WORLD=on`): the places and people around the Valley
    Inn, from the pack extension `extensions/inn_world/`.
  - `"antagonist"` (`WORLD_ANTAGONIST=on`, needs `inn_world`): the Tinjacks,
    from `extensions/antagonist/`.
  - `"hierarchical_locations"` (default on; `HIERARCHICAL_LOCATIONS=off`
    turns it off): movement uses
    the place tree (`parent`), see `TalesForge.Game.Movement`.

  Design: ex-tales-forge
  `docs/design-tin-valley-world.md`.
  """

  alias TalesForge.Config

  @known ~w(inn_world antagonist hierarchical_locations)
  @requires %{"antagonist" => "inn_world"}

  @typedoc "A known feature name."
  @type t :: String.t()

  @doc ~S"""
  The known features, in load order.

      iex> TalesForge.Game.Features.all()
      ["inn_world", "antagonist", "hierarchical_locations"]
  """
  @spec all() :: [t()]
  def all, do: @known

  @doc """
  The features a new session gets from the env flags; `antagonist` only
  together with `inn_world`.
  """
  @spec for_new_session() :: [t()]
  def for_new_session do
    [
      {"inn_world", Config.inn_world?()},
      {"antagonist", Config.world_antagonist?()},
      {"hierarchical_locations", Config.hierarchical_locations?()}
    ]
    |> Enum.filter(fn {_feature, on?} -> on? end)
    |> Enum.map(fn {feature, _on?} -> feature end)
    |> normalize()
  end

  @doc ~S"""
  Known features in load order, without duplicates and without features whose
  requirement is missing.

      iex> TalesForge.Game.Features.normalize(["antagonist", "inn_world", "nope"])
      ["inn_world", "antagonist"]
      iex> TalesForge.Game.Features.normalize(["antagonist"])
      []
  """
  @spec normalize([String.t()] | nil) :: [t()]
  def normalize(features) do
    wanted = MapSet.new(List.wrap(features))

    Enum.filter(@known, fn feature ->
      MapSet.member?(wanted, feature) and
        (is_nil(@requires[feature]) or MapSet.member?(wanted, @requires[feature]))
    end)
  end

  @doc ~S"""
  The features of a world_state (or intent context).

      iex> TalesForge.Game.Features.of(%{"features" => ["inn_world"]})
      ["inn_world"]
      iex> TalesForge.Game.Features.of(%{})
      []
  """
  @spec of(map() | nil) :: [t()]
  def of(%{"features" => features}) when is_list(features), do: normalize(features)
  def of(_world), do: []

  @doc "True when the world_state has `feature`."
  @spec on?(map() | nil, t()) :: boolean()
  def on?(world, feature), do: feature in of(world)
end
