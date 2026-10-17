defmodule TalesForge.Game.Prompts do
  @moduledoc """
  Prompt files and message assembly for the narration calls (scene and GM turn).

  Message order is fixed so xAI's prompt cache can reuse the longest prefix:

  1. system: `narrator_system.txt` — shared table voice, identical for every call
  2. system: the adventure's rules — identical for the scene call and every GM turn
  3. system: the task (`scene_system.txt` or `gm_system.txt`)
  4. user: session-stable content (character sheet, adventure, opening scene)
  5. user: per-turn state (facts, location, inventory, NPCs, recent turns, and
     for a GM turn the server resolution, the validated PlayerAction and handler)

  1–2 are byte-identical between the scene call and the GM calls, so with the
  same `x-grok-conv-id` the opening scene warms the cache for GM turn 1. Nothing
  in 1–4 may change per turn; `test/ex_tales_forge/game/prompt_prefix_test.exs`
  guards this.
  """

  alias TalesForge.Game.Schemas.{HandlerResult, PlayerAction}
  alias TalesForge.Prompt
  alias TalesForge.Prompt.{Ctx, Profile}

  @doc "System prompt of the intent step (`priv/prompts/intent_system.txt`)."
  @spec intent_system() :: String.t()
  def intent_system, do: read_prompt("intent_system.txt")

  @doc "Shared table voice, message 1 of every narration call (`narrator_system.txt`)."
  @spec narrator_system() :: String.t()
  def narrator_system, do: read_prompt("narrator_system.txt")

  @doc """
  Task prompt of a GM turn, message 3, for an app role. The
  prompt is the fragments in `priv/prompts/gm_system/` that
  `TalesForge.Prompt.Profile.gm_task_fragments/1` lists for the role.
  """
  @spec gm_system(atom()) :: String.t()
  def gm_system(role \\ :local) do
    %Ctx{call: :gm, role: role}
    |> Profile.gm_task_fragments()
    |> Enum.map_join(&read_prompt("gm_system/#{&1}.txt"))
  end

  @doc "Task prompt of the opening/arrival scene, message 3 (`scene_system.txt`)."
  @spec scene_system() :: String.t()
  def scene_system, do: read_prompt("scene_system.txt")

  @doc "Messages for the opening/arrival scene call."
  @spec scene_messages(map()) :: [%{role: String.t(), content: String.t()}]
  def scene_messages(gm_context), do: messages(gm_context, :scene, data: [])

  defmodule GmTurn do
    @moduledoc """
    What a GM turn adds to the context in
    `TalesForge.Game.Prompts.gm_messages/3`: the server's mechanical
    resolution, the validated PlayerAction, the handler and the turn number.
    """

    alias TalesForge.Game.Schemas.{HandlerResult, MechanicalResolution, PlayerAction}

    @enforce_keys [:mechanical, :player_action, :handler, :turn_number]
    defstruct @enforce_keys

    @type t :: %__MODULE__{
            mechanical: MechanicalResolution.t() | nil,
            player_action: PlayerAction.t(),
            handler: HandlerResult.t(),
            turn_number: integer()
          }
  end

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
    TalesForge.Game.Context.format_gm_prompt(TalesForge.Game.Context.build_gm_context(session))
  end

  @doc """
  Load the global rules in `priv/rules` (used by adventures without their own rules folder).
  """
  @spec load_rules() :: String.t()
  def load_rules do
    load_rules_from_dir(priv_path("rules"))
  end

  @doc """
  Load rules for a specific adventure, if it has its own pack in priv/adventures/<adventure_id>/rules.

  Falls back to global rules if no pack-specific rules/ directory is found.
  This is the key to making fully self-contained game packs (e.g. "Drakar och Demoner")
  actually drive the GM prompts.
  """
  @spec load_rules(String.t() | nil) :: String.t()
  def load_rules(adventure_id) when is_binary(adventure_id) do
    pack_rules_dir = Path.join([priv_path("adventures"), adventure_id, "rules"])

    if File.dir?(pack_rules_dir) and has_markdown?(pack_rules_dir) do
      load_rules_from_dir(pack_rules_dir)
    else
      load_rules_from_dir(priv_path("rules"))
    end
  end

  def load_rules(_other), do: load_rules_from_dir(priv_path("rules"))

  @doc """
  Load rules from an explicit directory (used by the Importer and for pack-aware sessions).
  Walks recursively and concatenates all .md files, sorted by path.
  """
  @spec load_rules_from_dir(String.t()) :: String.t()
  def load_rules_from_dir(dir) when is_binary(dir) do
    Path.wildcard(Path.join(dir, "**/*.md"))
    |> Enum.sort()
    |> Enum.map_join("\n\n---\n\n", fn path ->
      "### #{Path.relative_to(path, dir)}\n\n#{File.read!(path)}"
    end)
  end

  defp has_markdown?(dir) do
    Path.wildcard(Path.join(dir, "**/*.md")) != []
  end

  defp read_prompt(name), do: File.read!(priv_path("prompts/#{name}"))

  # Resolved at runtime: in a release priv lives under /app/lib/ex_tales_forge-<vsn>/priv,
  # not under the _build path a compile-time module attribute would capture.
  defp priv_path(rel), do: Path.join(:code.priv_dir(:ex_tales_forge), rel)
end
