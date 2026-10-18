defmodule TalesForge.Game.Turn do
  @moduledoc """
  One turn as one pipe over a `%Turn{}` struct (ex-tales-forge
  `docs/architecture.md`):

      {session, number}
      |> Turn.new({raw_action, intent}, opts)
      |> Turn.Premise.check()
      |> Turn.Mechanics.apply()
      |> Turn.Npcs.react()
      |> Turn.Notice.select()
      |> Turn.Prompt.build()
      |> Turn.Gm.narrate()
      |> Turn.Outcome.persist()
      |> Turn.result()

  The intent step (`Jev.classify`, `TalesForge.Game.JevIntent`) runs before
  the turn job, and its result is the `intent` field.

  Each stage writes its own field: `premise`, `outcome`, `npcs`, `notice`, `prompt`,
  `narration` and `result`. The feature flags and the role are read one time,
  in `new/3`. IO goes through `adapters` (`TalesForge.Game.Turn.Adapters`).
  A rejected action is data (`outcome.handler` has `"rejected" => true`). A
  failed GM call is data too: `narration` is `{:error, reason}`, and the
  stages after it pass the turn through.

  `cast` is the session's GM characters as the turn loaded them
  (`TalesForge.Game.Cast`, from their rows); the board carries them on
  through the turn (`board.cast`: a wound, a new minor foe, a gut reaction)
  to the store.
  """

  alias TalesForge.Characters
  alias TalesForge.Config
  alias TalesForge.Game.Cast
  alias TalesForge.Game.HistoryStrip
  alias TalesForge.Game.Schemas.PlayerAction
  alias TalesForge.Game.Turn.Adapters
  alias TalesForge.Intention
  alias TalesForge.Schemas.GameSession

  defstruct [
    :session,
    :number,
    :raw_action,
    :history_action,
    :intent,
    :intention,
    :role,
    :outcome,
    :notice,
    :prompt,
    :narration,
    :result,
    cast: %{},
    opts: [],
    flags: %{},
    injected: false,
    adapters: %Adapters{},
    premise: %{first: nil, findings: []},
    npcs: %{reactions: []}
  ]

  @type t :: %__MODULE__{
          session: GameSession.t(),
          number: integer(),
          raw_action: String.t(),
          history_action: String.t(),
          intent: PlayerAction.t(),
          intention: Intention.t(),
          role: atom(),
          outcome: map() | nil,
          notice: %{level: atom(), details: [String.t()]} | nil,
          prompt: map() | nil,
          narration: {:ok, struct()} | {:error, term()} | nil,
          result: {:ok, map()} | {:error, term()} | nil,
          cast: Cast.t(),
          opts: keyword(),
          flags: %{atom() => boolean()},
          injected: boolean(),
          adapters: Adapters.t(),
          premise: %{first: [map()] | nil, findings: [map()]},
          npcs: %{reactions: [map()]}
        }

  @doc """
  A new turn. Reads the feature flags and the role one time. `opts` are the
  intent options of `TalesForge.Game.TurnProcessor.run/3` plus `:adapters`,
  `:flags` and `:cast` (for tests; else `TalesForge.Characters.cast/1`).
  The session's `world_state["character"]`
  is the acting character, from its `characters` row
  (`TalesForge.Characters.put_sheet/1`, when the session is loaded); the
  turn plays its Intention (`intention`, `by: :human`).
  """
  @spec new({GameSession.t(), integer()}, {String.t(), PlayerAction.t()}, keyword()) :: t()
  def new({%GameSession{} = session, number}, {raw_action, %PlayerAction{} = intent}, opts \\ []) do
    flags = Keyword.get_lazy(opts, :flags, &read_flags/0)
    injected = flag?(flags, :history_strip_injection) and HistoryStrip.injected?(raw_action)

    %__MODULE__{
      session: session,
      number: number,
      raw_action: raw_action,
      history_action: if(injected, do: HistoryStrip.placeholder(), else: raw_action),
      intent: intent,
      intention: Intention.human(actor_id(session.world_state), intent),
      opts: opts,
      flags: flags,
      injected: injected
    }
    |> struct!(from_opts(opts, session.id))
  end

  # What the options give, else the defaults: the session's cast, the role
  # and the adapters.
  defp from_opts(opts, session_id) do
    [
      cast: Keyword.get_lazy(opts, :cast, fn -> Characters.cast(session_id) end),
      role: Keyword.get_lazy(opts, :role, &TalesForge.AppRole.role/0),
      adapters: Keyword.get(opts, :adapters, %Adapters{})
    ]
  end

  @doc "The feature flags of a turn, read from `TalesForge.Config`."
  @spec read_flags() :: %{atom() => boolean()}
  def read_flags do
    Map.merge(TalesForge.Prompt.Ctx.read_flags(), %{
      turn_premise_first: Config.turn_premise_first?(),
      turn_state_from_mechanics: Config.turn_state_from_mechanics?(),
      turn_apply_outcomes: Config.turn_apply_outcomes?(),
      history_strip_injection: Config.history_strip_injection?(),
      jev_catalogue_v2: Config.jev_catalogue_v2?()
    })
  end

  @doc "True when `flag` is on."
  @spec flag?(t() | map(), atom()) :: boolean()
  def flag?(%__MODULE__{flags: flags}, flag), do: flag?(flags, flag)
  def flag?(flags, flag) when is_map(flags), do: Map.get(flags, flag, false) == true

  @doc "The world state before the turn (`%{}` when the session has none)."
  @spec world_before(t()) :: map()
  def world_before(%__MODULE__{session: session}), do: session.world_state || %{}

  @doc "The result of the turn: `{:ok, payload}` or `{:error, reason}`."
  @spec result(t()) :: {:ok, map()} | {:error, term()}
  def result(%__MODULE__{narration: {:ok, _}, result: result}), do: result
  def result(%__MODULE__{narration: error}), do: error

  # The acting character's slug; a world the rules cannot read fails inside
  # the recorded rules step, not here.
  defp actor_id(%{"character" => %{"id" => id}}), do: id
  defp actor_id(_world), do: nil
end
