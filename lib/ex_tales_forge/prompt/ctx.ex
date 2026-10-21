defmodule TalesForge.Prompt.Ctx do
  @moduledoc """
  The input of a prompt (`TalesForge.Prompt`):

    * `call` — the call type: `:gm`, `:scene` or `:intent`;
    * `role` — the app role (`TalesForge.AppRole`): `:production`,
      `:playtest` or `:local`;
    * `flags` — the feature flags that change the prompt (`read_flags/0`);
    * `data` — the call's data (for a GM turn, the GM context of
      `TalesForge.Game.Context.build_gm_context/1` plus the turn values).
  """

  defstruct call: :gm, role: :local, flags: %{}, data: %{}

  @type t :: %__MODULE__{
          call: :gm | :scene | :intent,
          role: atom(),
          flags: map(),
          data: map()
        }

  @doc "A context for a narration call (`:gm` or `:scene`) from a GM context."
  @spec from_gm_context(map(), :gm | :scene, keyword()) :: t()
  def from_gm_context(gm_context, call, opts \\ []) do
    %__MODULE__{
      call: call,
      role: Keyword.get_lazy(opts, :role, &TalesForge.AppRole.role/0),
      flags: Keyword.get_lazy(opts, :flags, &read_flags/0),
      data: Map.merge(gm_context, Map.new(Keyword.get(opts, :data, [])))
    }
  end

  @doc """
  The feature flags that change the prompt, read from `TalesForge.Config`.
  A turn reads them once, at its start.
  """
  @spec read_flags() :: %{atom() => boolean()}
  def read_flags do
    %{
      turn_outcome_record: TalesForge.Config.turn_outcome_record?(),
      npc_dialogue_memory: TalesForge.Config.npc_dialogue_memory?(),
      npc_first_meeting: TalesForge.Config.npc_first_meeting?(),
      character_memory: TalesForge.Config.character_memory() == :on,
      npc_reactions: TalesForge.Config.npc_reactions?(),
      world_agents: TalesForge.Config.world_agents?(),
      skill_detail_level: TalesForge.Config.skill_detail_level?(),
      skill_split: TalesForge.Config.skill_split?(),
      combat_opposed: TalesForge.Config.combat_opposed?(),
      location_grid: TalesForge.Config.location_grid?()
    }
  end

  @doc "True when `flag` is on in `ctx`."
  @spec flag?(t(), atom()) :: boolean()
  def flag?(%__MODULE__{flags: flags}, flag), do: Map.get(flags, flag, false) == true
end
