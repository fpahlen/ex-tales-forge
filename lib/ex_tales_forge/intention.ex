defmodule TalesForge.Intention do
  @moduledoc """
  What one character means to do, and where that came from: the only place
  where a player character and an NPC differ (refactor plan step 10,
  `docs/plan-tf-refactor-2026-10-17.md`).

    * `by: :human` — the player's words, read by `Intent`/`JevIntent` into a
      `PlayerAction`. The persona runner (`bot`) comes in this way too.
    * `by: :gm` — the GM's updates (not yet an Intention).
    * `by: :system` — the rules: an NPC's gut reaction (`CharacterReactions`), a
      concern that waits (`GameCharacter.Actions.ReactToTime`), what an NPC hears
      (`GameCharacter.Actions.OnPlayerTalked`, `GameCharacter.Actions.OnOverheard`) and its
      initiative (`Initiative`).

  The turn applies them (`TalesForge.Game.Turn.Intentions`); nothing that
  makes an Intention writes state.

      iex> TalesForge.Intention.system("innkeep", {:remember, "A stranger asked for work."}, 48)
      %TalesForge.Intention{character_id: "innkeep", by: :system, action: {:remember, "A stranger asked for work."}, tick: 48}
  """

  alias TalesForge.Game.Schemas.PlayerAction

  @enforce_keys [:character_id, :by, :action]
  defstruct [:character_id, :by, :action, tick: nil]

  @typedoc "Where an Intention comes from."
  @type by :: :human | :gm | :system

  @typedoc """
  The action: the player's `PlayerAction`, or one of the rule actions
  `{:feel, mood}`, `{:wait, delta_ticks}`, `:speak_up`, `{:remember, summary}`
  and `{:warm, delta}`.
  """
  @type action ::
          PlayerAction.t()
          | nil
          | {:feel, map()}
          | {:wait, integer()}
          | :speak_up
          | {:remember, String.t()}
          | {:warm, number()}

  @type t :: %__MODULE__{
          character_id: String.t() | nil,
          by: by(),
          action: action(),
          tick: integer() | nil
        }

  @doc "The acting character's Intention from the player's words."
  @spec human(String.t() | nil, PlayerAction.t() | nil) :: t()
  def human(character_id, action),
    do: %__MODULE__{character_id: character_id, by: :human, action: action}

  @doc "A rule-made Intention of `character_id` at `tick`."
  @spec system(String.t(), action(), integer() | nil) :: t()
  def system(character_id, action, tick),
    do: %__MODULE__{character_id: character_id, by: :system, action: action, tick: tick}
end
