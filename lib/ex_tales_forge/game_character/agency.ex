defmodule TalesForge.GameCharacter.Agency do
  @moduledoc """
  What a pack NPC does on its own: the world-sim tick's view of the
  session's NPCs and its save, and the concern that waits, escalates and
  makes the NPC speak up (`TalesForge.GameCharacter.Initiative`).
  """

  alias TalesForge.GameCharacter.{Person, Rows}
  alias TalesForge.Repo

  @doc """
  The session's NPCs as the world-sim tick takes them
  (`TalesForge.Game.WorldSim.tick/1`): id, definition and runtime state.
  """
  @spec sim_people(Ecto.UUID.t()) :: [map()]
  def sim_people(session_id) when is_binary(session_id) do
    Enum.map(Rows.list(session_id), &to_sim/1)
  end

  @doc """
  The world-sim tick's people (`sim.people`) saved onto their rows, as
  steps of `multi`; each row is read in the step, so it sees the steps
  before it. The tick's people were read before the turn's trade, so their
  stock and coins are left as the row has them (`TalesForge.GameCharacter.Rows.changeset/2`).
  """
  @spec persist_tick_multi(Ecto.Multi.t(), Ecto.UUID.t(), map()) :: Ecto.Multi.t()
  def persist_tick_multi(multi, session_id, sim) when is_map(sim) do
    Enum.reduce(Map.get(sim, :people, []), multi, fn person, acc ->
      id = npc_id(person)

      Ecto.Multi.run(acc, {:npc, id}, fn _repo, _changes ->
        persist_tick(Rows.get(session_id, id), runtime(person))
      end)
    end)
  end

  defp persist_tick(%Person{} = inst, runtime),
    do: inst |> Rows.changeset(runtime) |> Repo.update()

  defp persist_tick(nil, _runtime), do: {:ok, nil}

  @doc """
  The NPC's current concern waits `delta_ticks` longer and escalates when
  it has waited long enough. Returns the concern's priority, its wait and
  whether the NPC is ready to speak up, or `:ok` when it has no concern.
  """
  @spec adjust_concern(Ecto.UUID.t(), String.t(), integer()) :: :ok | {:ok, map()}
  def adjust_concern(session_id, npc_id, delta_ticks) when is_integer(delta_ticks) do
    case Rows.get(session_id, npc_id) do
      %Person{runtime_state: %{"current_concern" => %{} = concern}} = inst ->
        wait_on_concern(inst, concern, delta_ticks)

      _ ->
        :ok
    end
  end

  # The concern waits `delta_ticks` longer, and escalates when it has waited
  # long enough.
  defp wait_on_concern(%Person{runtime_state: runtime} = inst, concern, delta_ticks) do
    waited = Map.get(runtime, "concern_wait_ticks", 0) + delta_ticks
    old_priority = Map.get(concern, "priority", 0)
    initiative_ready? = waited >= 4 and old_priority >= 8 and not initiative_emitted?(inst)
    {waiting, concern} = maybe_escalate_concern(waited, concern)
    priority = Map.get(concern, "priority", 0)

    runtime =
      runtime
      |> Map.put("current_concern", concern)
      |> Map.put("concern_wait_ticks", waiting)
      |> maybe_reset_initiative_emitted(old_priority, priority)

    Rows.update!(inst, runtime)

    {:ok,
     %{
       concern_priority: priority,
       concern_wait_ticks: waiting,
       initiative_pending: initiative_ready?
     }}
  end

  @doc """
  What the NPC says when it speaks up about its concern; `nil` when it has
  no line written for it, so the play page shows nothing rather than a
  stage direction with no speech.
  """
  @spec initiative_text(Person.t()) :: String.t() | nil
  def initiative_text(%Person{npc_id: "worried_merchant"} = inst) do
    focus =
      inst.runtime_state
      |> Map.get("current_concern", %{})
      |> Map.get("focus", "the stolen ledger")

    case focus do
      "stolen ledger" ->
        "Henrik Bale steps toward you, voice tight. \"Please — if you've heard who took that ledger, tell me before rumors spread.\""

      "ruined reputation" ->
        "Henrik glances at the crowd, then lowers his voice. \"I can't afford another whisper campaign against my name.\""

      _ ->
        "Henrik Bale wrings his hands. \"It's this business with #{focus} — I need answers.\""
    end
  end

  def initiative_text(%Person{npc_id: "marta_kellen"} = inst) do
    focus =
      inst.runtime_state
      |> Map.get("current_concern", %{})
      |> Map.get("focus", "the missing ledger")

    case focus do
      "missing ledger" ->
        "Marta wipes the bar and catches your eye. \"That ledger didn't walk off on its own. If you've heard anything, I need to know before sundown.\""

      "unwanted attention in her tavern" ->
        "Marta's voice stays low but firm. \"Too many strangers tonight. Keep your business quiet, or take it outside.\""

      _ ->
        "Marta hesitates, then speaks up. \"Something's been bothering me — #{focus}.\""
    end
  end

  def initiative_text(%Person{}), do: nil

  @doc "Marks that the NPC has spoken up about its concern, at `world_tick`."
  @spec mark_initiative_emitted(Person.t(), integer() | nil) :: :ok
  def mark_initiative_emitted(%Person{} = inst, world_tick) do
    runtime =
      inst.runtime_state
      |> Map.put("initiative_emitted", true)
      |> Map.put("initiative_emitted_at_tick", world_tick)

    Rows.update!(inst, runtime)
    :ok
  end

  @doc "The priority of the NPC's current concern, 0 when it has none."
  @spec concern_priority(Person.t() | nil) :: integer()
  def concern_priority(%Person{} = inst) do
    case Map.get(inst.runtime_state, "current_concern") do
      %{} = concern -> Map.get(concern, "priority", 0)
      _ -> 0
    end
  end

  def concern_priority(nil), do: 0

  defp to_sim(%Person{} = inst) do
    %{
      npc_id: inst.npc_id,
      definition: inst.personality,
      runtime_state: inst.runtime_state
    }
  end

  defp npc_id(%{npc_id: id}), do: id
  defp npc_id(%{"npc_id" => id}), do: id

  defp runtime(%{runtime_state: state}), do: state
  defp runtime(%{"runtime_state" => state}), do: state

  defp maybe_escalate_concern(waiting, concern) when waiting >= 4 do
    priority = min(10, Map.get(concern, "priority", 5) + 1)
    maybe_escalate_concern(waiting - 4, Map.put(concern, "priority", priority))
  end

  defp maybe_escalate_concern(waiting, concern), do: {waiting, concern}

  defp initiative_emitted?(%Person{} = inst),
    do: Map.get(inst.runtime_state, "initiative_emitted", false)

  defp maybe_reset_initiative_emitted(runtime, old_priority, new_priority)
       when new_priority > old_priority do
    runtime
    |> Map.put("initiative_emitted", false)
    |> Map.delete("initiative_emitted_at_tick")
  end

  defp maybe_reset_initiative_emitted(runtime, _old_priority, _new_priority), do: runtime
end
