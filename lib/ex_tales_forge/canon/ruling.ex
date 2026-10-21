defmodule TalesForge.Canon.Ruling do
  @moduledoc """
  A founder decision on one difference (`TalesForge.Canon.decide/1`): the
  game `session`, the `difference`, the `action` (`"session_only"`,
  `"add_to_canon"` or `"error"`) and the `founder` who decided.
  """

  alias TalesForge.Canon.{Decision, Difference, SeedPatch}
  alias TalesForge.Schemas.GameSession

  @enforce_keys [:session, :difference]
  defstruct [:session, :difference, action: nil, founder: nil]

  @type t :: %__MODULE__{
          session: GameSession.t(),
          difference: Difference.t(),
          action: String.t() | nil,
          founder: String.t() | nil
        }

  @doc """
  The `TalesForge.Canon.Decision` changeset of the ruling. An `"add_to_canon"`
  ruling carries the proposed seed patch.
  """
  @spec decision(t()) :: Ecto.Changeset.t()
  def decision(%__MODULE__{session: %GameSession{} = session, difference: %Difference{} = d} = r) do
    patch =
      if r.action == "add_to_canon",
        do: SeedPatch.propose(d, get_in(session.world_state || %{}, ["adventure_id"]))

    Decision.changeset(%Decision{}, %{
      game_session_id: session.id,
      diff_key: d.key,
      action: r.action,
      founder: r.founder,
      difference: Difference.to_map(d),
      seed_patch: patch
    })
  end
end
