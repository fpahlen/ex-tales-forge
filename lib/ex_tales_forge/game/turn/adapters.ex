defmodule TalesForge.Game.Turn.Adapters do
  @moduledoc """
  The IO of a turn (`TalesForge.Game.Turn`). The stages call these functions
  and do no other IO, so a test gives plain functions instead of mocks.

    * `npc` — the NPC reactions (`TalesForge.Game.NpcReactions.react/1`; the
      Jev call with its timeout, `NPC_REACTIONS_TIMEOUT_MS`, default 600 ms);
    * `gm` — the GM call (`TalesForge.LLM.complete_turn/5`);
    * `stream` — gets each GM text chunk (`{:turn_stream, chunk}` on the
      session topic);
    * `profiles` — the present NPCs for the noticed details
      (`TalesForge.NPC.notice_profiles/2`; only with `SKILL_DETAIL_LEVEL=on`);
    * `store` — persists the turn and signals
      (the persist step, `TalesForge.Game.Turn.Store.persist/1`);
    * `fighter` — the combat fighter of one NPC
      (`TalesForge.NPC.combat_profile/2`; only with `COMBAT_OPPOSED=on`);
    * `character_rules` — the character defaults rules of an adventure, for
      a minor foe (`TalesForge.Characters.Defaults.rules/1`; only with
      `COMBAT_OPPOSED=on`).
  """

  defstruct npc: &TalesForge.Game.NpcReactions.react/1,
            gm: &TalesForge.LLM.complete_turn/5,
            stream: &__MODULE__.broadcast/2,
            profiles: &TalesForge.NPC.notice_profiles/2,
            store: &TalesForge.Game.Turn.Store.persist/1,
            fighter: &TalesForge.NPC.combat_profile/2,
            character_rules: &TalesForge.Characters.Defaults.rules/1

  @type t :: %__MODULE__{
          npc: (TalesForge.Game.NpcReactions.Moment.t() -> {[map()], map()}),
          gm: function(),
          stream: (String.t(), String.t() -> term()),
          profiles: (String.t(), [String.t()] -> [map()]),
          store: (TalesForge.Game.Turn.Store.t() -> {:ok, map()} | {:error, term()}),
          fighter: (String.t(), String.t() -> map() | nil),
          character_rules: (String.t() | nil -> map())
        }

  @doc "The default `stream` adapter: broadcasts the chunk on the session topic."
  @spec broadcast(String.t(), String.t()) :: :ok | {:error, term()}
  def broadcast(session_id, chunk),
    do: TalesForge.PubSub.GameSession.broadcast(session_id, {:turn_stream, chunk})
end
