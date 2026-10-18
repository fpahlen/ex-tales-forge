defmodule TalesForge.World.TurnRequest do
  @moduledoc """
  One turn for `TalesForge.World.Instance.run_turn/2`: what
  `TalesForge.Game.TurnProcessor.run/3` takes, plus what the turn's Task
  inherits from the process that asked for it.

    * `session_id`, `raw_action`, `player_action` (the encoded
      `PlayerAction` map) and `opts`: the arguments of
      `TurnProcessor.run/3`.
    * `callers`: the asking process and its `$callers`, so the Task works on
      its behalf (Ecto sandbox and `Req.Test` ownership in tests, Logger
      metadata lineage).
    * `rand`: the asking process's `:rand` state (`:rand.export_seed/0`), so
      the dice roll as if the turn ran in that process; `run_turn/2` hands
      the state back afterwards. `:undefined` when it has none.
    * `logger`: the asking process's Logger metadata (the Oban job's).
  """

  require Logger

  @enforce_keys [:session_id, :raw_action, :player_action]
  defstruct [
    :session_id,
    :raw_action,
    :player_action,
    opts: [],
    callers: [],
    rand: :undefined,
    logger: []
  ]

  @type t :: %__MODULE__{
          session_id: Ecto.UUID.t(),
          raw_action: String.t(),
          player_action: map(),
          opts: keyword(),
          callers: [pid()],
          rand: term(),
          logger: keyword()
        }

  @doc """
  The request for a turn asked for by the calling process.

      iex> r = TalesForge.World.TurnRequest.new("s1", {"I wait", %{}}, founder: "f")
      iex> {r.session_id, r.raw_action, r.opts, hd(r.callers) == self()}
      {"s1", "I wait", [founder: "f"], true}
  """
  @spec new(Ecto.UUID.t(), {String.t(), map()}, keyword()) :: t()
  def new(session_id, {raw_action, player_action}, opts \\ []) do
    %__MODULE__{
      session_id: session_id,
      raw_action: raw_action,
      player_action: player_action,
      opts: opts,
      callers: [self() | Process.get(:"$callers", [])],
      rand: :rand.export_seed(),
      logger: Logger.metadata()
    }
  end
end
