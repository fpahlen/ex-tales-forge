defmodule TalesForge.Game.Absent do
  @moduledoc """
  A trade needs both parties in the scene. The refusal for a buy, sell or
  trade with a person of the session who is not present (Case's "castle"
  case: the knife sold to Hilde at the inn while she was at her forge).
  """

  alias TalesForge.Game.Inventory
  alias TalesForge.GameCharacter.Roster

  @doc ~s(The reason "<name> isn't here." when `action` names a person of `session` not in `world`'s `"present_npcs"`, or nil.)
  @spec reason(
          TalesForge.Schemas.GameSession.t(),
          TalesForge.Game.Schemas.SingleAction.t(),
          map()
        ) :: String.t() | nil
  def reason(%{id: session_id}, action, world) do
    id = Inventory.named_trader(action)

    case id not in ["" | List.wrap(world["present_npcs"])] && Roster.traders(session_id, [id]) do
      %{^id => %{name: name}} -> "#{name} isn't here."
      _present_or_nobody -> nil
    end
  end
end
