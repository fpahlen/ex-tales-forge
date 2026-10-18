defmodule TalesForge.Game.Train do
  @moduledoc """
  Training with an NPC trainer (the `train` handler).

  A session qualifies when the skill is named, the trainer is present, has an
  authored level in the skill at least 5 above the character's, charges a fee
  the character can pay (per day, one-day minimum) and the character is not
  down or dead.

  The session is **one free improvement attempt** (no LP spent) with **+5**
  on the d100 (`TalesForge.Game.Progression.train/3`, decision 2026-10-07).
  No LP or failures are needed.
  """

  alias TalesForge.Game.Inventory
  alias TalesForge.Game.Mechanics
  alias TalesForge.Game.Progression
  alias TalesForge.Game.WorldClock

  defmodule Session do
    @moduledoc """
    Who takes part in a training session: the character, the trainer's
    definition (`nil` when unknown) and the ids of the NPCs present.
    """
    defstruct [:character, :trainer, present_ids: []]

    @typedoc "The character, the trainer and who is present."
    @type t :: %__MODULE__{
            character: map(),
            trainer: map() | nil,
            present_ids: [String.t()] | nil
          }
  end

  @doc """
  Runs a training action. Returns the character, the attempts (tagged with
  `trainer_npc_id`), `"took_place"` or `"declined"`, and the ticks that pass
  (one when declined). Option: `:improvement_rolls` (injected d100s for
  tests).
  """
  @spec apply(Session.t(), struct(), keyword()) ::
          {map(), [map()], String.t(), non_neg_integer()}
  def apply(%Session{character: character} = session, action, opts \\ []) do
    params = action.parameters || %{}
    skill = Mechanics.normalize_skill_name(Map.get(params, "skill"))
    ticks = WorldClock.clamp_wait(Map.get(params, "ticks"))
    npc_id = action.target

    case qualify(session, skill, ticks) do
      {:ok, fee} ->
        rolls = opts[:improvement_rolls] || %{}
        {taught, entry} = Progression.train(character, skill, rolls)
        coins = Inventory.deduct_coins(Map.get(taught, "coins", %{}), fee)
        taught = Map.put(taught, "coins", coins)
        {taught, [Map.put(entry, "trainer_npc_id", npc_id)], "took_place", ticks}

      {:error, _} ->
        {character, [], "declined", 1}
    end
  end

  @doc """
  Whether a training session may take place: `{:ok, fee_copper}` or
  `{:error, reason}`.
  """
  @spec qualify(Session.t(), String.t() | nil, integer()) ::
          {:ok, pos_integer()} | {:error, atom()}
  def qualify(%Session{} = session, skill, ticks),
    do: session |> facts(skill) |> verdict(ticks)

  defp facts(%Session{character: character, trainer: npc_def, present_ids: present_ids}, skill) do
    %{
      skill: skill,
      npc_id: Map.get(npc_def || %{}, "id"),
      present_ids: List.wrap(present_ids),
      npc_skill: get_in(npc_def || %{}, ["skills", skill]),
      fee_rate: Map.get(npc_def || %{}, "fee_copper"),
      raw: character |> get_in(["skills", skill]) |> to_int(0),
      vitality: training_vitality(character),
      coins: Map.get(character, "coins", %{})
    }
  end

  defp verdict(%{skill: skill, npc_id: npc_id, npc_skill: npc_skill} = f, ticks) do
    cond do
      not is_binary(skill) or skill == "" ->
        {:error, :no_skill}

      not is_binary(npc_id) or npc_id == "" ->
        {:error, :no_npc}

      npc_id not in f.present_ids ->
        {:error, :not_present}

      not is_integer(npc_skill) ->
        {:error, :no_skill_rating}

      npc_skill < f.raw + Progression.trainer_bonus() ->
        {:error, :gap}

      true ->
        paid_verdict(f, ticks)
    end
  end

  defp paid_verdict(%{fee_rate: fee_rate} = f, ticks) do
    cond do
      not (is_integer(fee_rate) and fee_rate > 0) ->
        {:error, :no_fee}

      Inventory.coin_total_copper(f.coins) < session_fee(fee_rate, ticks) ->
        {:error, :cannot_pay}

      f.vitality not in ["ok", "hurt"] ->
        {:error, :vitality}

      true ->
        {:ok, session_fee(fee_rate, ticks)}
    end
  end

  @doc """
  The fee for a session of `ticks`: the daily rate per started day, at least
  one day.

      iex> TalesForge.Game.Train.session_fee(50, 288)
      150
  """
  @spec session_fee(pos_integer(), integer()) :: pos_integer()
  def session_fee(fee_copper, ticks) when is_integer(fee_copper) and fee_copper > 0 do
    days = max(1, ceil(ticks / WorldClock.ticks_per_day()))
    fee_copper * days
  end

  # Stamped down/dead without wounding — Mechanics.vitality/1 derives down from wounds.
  defp training_vitality(character) do
    case Map.get(character, "vitality") do
      vitality when vitality in ["down", "dead"] -> vitality
      _ -> Mechanics.vitality(character)
    end
  end

  defp to_int(value, _default) when is_integer(value), do: value
  defp to_int(value, _default) when is_float(value), do: trunc(value)
  defp to_int(_, default), do: default
end
