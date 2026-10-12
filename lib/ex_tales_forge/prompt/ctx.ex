defmodule TalesForge.Prompt.Ctx do
  @moduledoc """
  The input of a prompt (`TalesForge.Prompt`):

    * `call` — the call type: `:gm`, `:scene` or `:intent`;
    * `role` — the app role (`TalesForge.AppRole`): `:production`,
      `:playtest` or `:local`;
    * `variant` — the session's behaviour variant (`TalesForge.Game.Variant`);
    * `flags` — the feature flags that change the prompt;
    * `data` — the call's data (for a GM turn, the GM context of
      `TalesForge.Game.Context.build_gm_context/1` plus the turn values).
  """

  alias TalesForge.Game.Variant

  defstruct call: :gm, role: :local, variant: "default", flags: %{}, data: %{}

  @type t :: %__MODULE__{
          call: :gm | :scene | :intent,
          role: atom(),
          variant: String.t(),
          flags: map(),
          data: map()
        }

  @doc "A context for a narration call (`:gm` or `:scene`) from a GM context."
  @spec from_gm_context(map(), :gm | :scene, keyword()) :: t()
  def from_gm_context(gm_context, call, opts \\ []) do
    %__MODULE__{
      call: call,
      role: Keyword.get_lazy(opts, :role, &TalesForge.AppRole.role/0),
      variant: Variant.of(Map.get(gm_context, :world_state)),
      flags: Keyword.get(opts, :flags, %{}),
      data: Map.merge(gm_context, Map.new(Keyword.get(opts, :data, [])))
    }
  end

  @doc "True for the baseline variant."
  @spec baseline?(t()) :: boolean()
  def baseline?(%__MODULE__{variant: variant}), do: variant == "baseline"
end
