defmodule TalesForge.Game.Turn.Intentions do
  @moduledoc """
  The turn applies the rule-made Intentions of its characters
  (`TalesForge.Intention`, `by: :system`); the code that makes them writes
  nothing.

    * `feel/2`, in the NPC stage (`TalesForge.Game.Turn.Npcs`): the NPCs'
      gut reactions go on their characters in the turn's cast
      (`runtime["reaction"]`), and so to their `characters` rows.
    * `apply_all/2`, in the turn transaction (`TalesForge.Game.Turn.Store`):
      what the NPCs heard and how long their concerns waited
      (`TalesForge.NPCSignals.intentions/1`), on their character rows. It
      returns the initiative payloads, which the store broadcasts after the
      commit.
  """

  alias TalesForge.Game.Cast
  alias TalesForge.Intention
  alias TalesForge.NPC
  alias TalesForge.NPCInitiative

  @doc """
  The cast (`TalesForge.Game.Cast`) with the `{:feel, mood}` Intentions as
  each character's gut reaction, `runtime["reaction"]`. A character that is
  not in the cast is left out.

      iex> cast = %{"innkeep" => %TalesForge.GameCharacter{slug: "innkeep"}}
      iex> feel = TalesForge.Intention.system("innkeep", {:feel, %{"emotion" => "wary"}}, nil)
      iex> TalesForge.Game.Turn.Intentions.feel(cast, [feel])["innkeep"].runtime
      %{"reaction" => %{"emotion" => "wary"}}
      iex> TalesForge.Game.Turn.Intentions.feel(cast, []) == cast
      true
  """
  @spec feel(Cast.t(), [Intention.t()]) :: Cast.t()
  def feel(cast, intentions) do
    Enum.reduce(intentions, cast, fn
      %Intention{character_id: id, action: {:feel, mood}}, acc when is_map_key(acc, id) ->
        Map.update!(acc, id, &%{&1 | runtime: Map.put(&1.runtime, "reaction", mood)})

      _intention, acc ->
        acc
    end)
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
