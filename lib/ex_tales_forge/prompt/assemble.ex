defmodule TalesForge.Prompt.Assemble do
  @moduledoc """
  Puts a narration call together: the sections `TalesForge.Prompt.Profile`
  lists for the call, rendered by `TalesForge.Prompt` into messages (or, for
  tests and debugging, one flat string).

  The message order and the prompt-cache rules are in
  `TalesForge.Game.Prompts`; the context comes from
  `TalesForge.Game.Context`. Neither calls back here.
  """

  alias TalesForge.Game.Context
  alias TalesForge.Game.Prompts.GmTurn
  alias TalesForge.Game.Schemas.{HandlerResult, PlayerAction}
  alias TalesForge.Prompt
  alias TalesForge.Prompt.{Ctx, Profile}

  @doc "Messages for the opening/arrival scene call."
  @spec scene_messages(map()) :: [%{role: String.t(), content: String.t()}]
  def scene_messages(gm_context), do: messages(gm_context, :scene, data: [])

  @doc """
  Messages for a GM turn. Per-turn content, including the action, goes last.
  `opts[:role]` picks the app role (default `TalesForge.AppRole.role/1`).
  """
  @spec gm_messages(map(), GmTurn.t(), keyword()) :: [%{role: String.t(), content: String.t()}]
  def gm_messages(
        gm_context,
        %GmTurn{player_action: %PlayerAction{}, handler: %HandlerResult{}} = turn,
        opts \\ []
      ) do
    messages(gm_context, :gm, Keyword.put(opts, :data, Map.from_struct(turn)))
  end

  # `opts`: `:role` (default `TalesForge.AppRole.role/0`), `:flags` and the
  # call's `:data`.
  defp messages(gm_context, call, opts) do
    ctx = Ctx.from_gm_context(gm_context, call, opts)

    ctx
    |> Prompt.new()
    |> Prompt.add_all(Profile.sections(ctx))
    |> Prompt.to_messages()
  end

  @doc "The whole scene context of a session as one flat string (for tests and debugging)."
  @spec build_scene_user(TalesForge.Schemas.GameSession.t()) :: String.t()
  def build_scene_user(%TalesForge.Schemas.GameSession{} = session) do
    session |> Context.build_gm_context() |> format_gm_prompt()
  end

  @doc """
  The whole GM/scene context as one flat string: rules, then session-stable
  content, then per-turn state. The LLM receives the same sections as separate
  messages (see `gm_messages/3`); this flat view is for
  tests and debugging.
  """
  @spec format_gm_prompt(map()) :: String.t()
  def format_gm_prompt(context) do
    [context.rules, session_stable_section(context), per_turn_section(context)]
    |> join_sections()
  end

  @doc """
  Content that stays the same for the whole session (until the opening scene is
  replaced): the character's fixed sheet, the adventure, and the opening scene
  the player has already heard. Never put per-turn values (coins, wounds,
  inventory, turn numbers, clocks, NPC moods) here: it sits before the per-turn
  state so the prompt cache can reuse it on every turn.
  """
  @spec session_stable_section(map()) :: String.t()
  def session_stable_section(context), do: slot_text(context, :session)

  @doc "Everything that can change from turn to turn. Always last in the prompt."
  @spec per_turn_section(map()) :: String.t()
  def per_turn_section(context), do: slot_text(context, :turn)

  # The scene profile: the per-turn state with no GM turn tail.
  defp slot_text(context, slot) do
    ctx = Ctx.from_gm_context(context, :scene)

    ctx
    |> Prompt.new()
    |> Prompt.add_all(Profile.sections(ctx))
    |> Prompt.render_slot(slot)
  end

  defp join_sections(sections) do
    sections
    |> Enum.reject(&(is_nil(&1) or &1 == ""))
    |> Enum.join("\n\n---\n\n")
  end
end
