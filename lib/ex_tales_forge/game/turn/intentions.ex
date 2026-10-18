defmodule TalesForge.Game.Turn.Intentions do
  @moduledoc """
  The turn applies the rule-made Intentions of its characters
  (`TalesForge.Intention`, `by: :system`); the code that makes them writes
  nothing.

    * `feel/2`, in the NPC stage (`TalesForge.Game.Turn.Npcs`): the NPCs'
      gut reactions become their moods in `world_state["npc_moods"]`.
    * `apply_all/2`, in the turn transaction (`TalesForge.Game.Turn.Store`):
      what the NPCs heard and how long their concerns waited
      (`TalesForge.NPCSignals.intentions/1`), on their NPC instances. It
      returns the initiative payloads, which the store broadcasts after the
      commit.
  """

  alias TalesForge.Intention
  alias TalesForge.NPC
  alias TalesForge.NPCInitiative

  @doc """
  The world with the `{:feel, mood}` Intentions as each NPC's mood in
  `"npc_moods"`; the world as it is when there are none.

      iex> feel = TalesForge.Intention.system("innkeep", {:feel, %{"emotion" => "wary"}}, nil)
      iex> TalesForge.Game.Turn.Intentions.feel(%{"npc_moods" => %{"smith" => %{}}}, [feel])
      %{"npc_moods" => %{"smith" => %{}, "innkeep" => %{"emotion" => "wary"}}}
      iex> TalesForge.Game.Turn.Intentions.feel(%{}, [])
      %{}
  """
  @spec feel(map(), [Intention.t()]) :: map()
  def feel(world, []), do: world

  def feel(world, intentions) do
    moods =
      Enum.reduce(intentions, world["npc_moods"] || %{}, fn
        %Intention{character_id: id, action: {:feel, mood}}, acc -> Map.put(acc, id, mood)
      end)

    Map.put(world, "npc_moods", moods)
  end

  @doc """
  Applies the NPC Intentions of session `session_id` in order. A
  `:speak_up` only speaks when the `{:wait, _}` before it, for the same NPC,
  found the concern ready. Returns the initiative payloads to broadcast.
  """
  @spec apply_all(Ecto.UUID.t(), [Intention.t()]) :: [map()]
  def apply_all(session_id, intentions) do
    {payloads, _ready} =
      Enum.reduce(intentions, {[], MapSet.new()}, &apply_one(session_id, &1, &2))

    Enum.reverse(payloads)
  end

  defp apply_one(session_id, %Intention{character_id: id, action: {:wait, delta}}, {out, ready}) do
    case NPC.adjust_concern(session_id, id, delta) do
      {:ok, %{initiative_pending: true}} -> {out, MapSet.put(ready, id)}
      _ -> {out, MapSet.delete(ready, id)}
    end
  end

  defp apply_one(session_id, %Intention{character_id: id, action: :speak_up} = i, {out, ready}) do
    with true <- MapSet.member?(ready, id),
         {:ok, payload} <- NPCInitiative.speak_up(session_id, id, i.tick) do
      {[payload | out], ready}
    else
      _ -> {out, ready}
    end
  end

  defp apply_one(session_id, %Intention{action: {:remember, summary}} = i, acc) do
    :ok =
      NPC.record_memory(%NPC.Note{
        session_id: session_id,
        npc_id: i.character_id,
        summary: summary,
        tick: i.tick
      })

    acc
  end

  defp apply_one(session_id, %Intention{character_id: id, action: {:warm, delta}}, acc) do
    {:ok, _score} = NPC.bump_relationship(session_id, id, delta)
    acc
  end
end
