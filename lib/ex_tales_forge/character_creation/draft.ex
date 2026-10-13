defmodule TalesForge.CharacterCreation.Draft do
  @moduledoc """
  A player character being created. Pure data, kept by whoever drives creation
  (the creation screen or the persona runner) and changed only through
  `TalesForge.CharacterCreation`.

  * `seed_key` seeds the small per-character variation in the derived OCEAN, so
    a draft gives the same character every time it is finalised.
  * `model` is the creation model for the stats: `"point_buy"` (the player
    spends points) or `"stat_roll"` (the server rolls the dice).
  * `base_stats` are the stats before the race modifier: the point-buy stats,
    or the rolled stats in the dice model.
  * `rolled_stats` is the last dice roll (`nil` before the first roll). The
    draft keeps it when the player goes back to point buy, so a new roll needs
    the re-roll.
  * `rerolls_left` is the number of re-rolls that the player can still use.
  * `race_picks` are the stats chosen for a race bonus with a choice (Human: any
    two; Elf: INT or WIS).
  * `occupation` is the past occupation (an id from the `defaults.json`
    occupations the rules allow), which gives free skill levels.
  * `skills` are the levels set for skills (suggested, or by the player). A
    skill's level is the higher of this and its free level (class package,
    race bonus, past occupation); the levels above the free one are bought
    with skill points. A new race, class or occupation keeps the levels, so
    free levels that now cover them give their points back.
  * `edited` holds the parts the player has set (`:stats`, `:race_picks`,
    `:occupation`, `:skills`), so a new race or class re-suggests only what
    the player hasn't touched.
  """

  @enforce_keys [:adventure_id, :seed_key]
  defstruct adventure_id: nil,
            seed_key: nil,
            name: "",
            race: "human",
            class: "none",
            occupation: nil,
            model: "point_buy",
            base_stats: %{},
            rolled_stats: nil,
            rerolls_left: 0,
            race_picks: [],
            skills: %{},
            edited: MapSet.new()

  @type t :: %__MODULE__{
          adventure_id: String.t(),
          seed_key: String.t(),
          name: String.t(),
          race: String.t(),
          class: String.t(),
          occupation: String.t() | nil,
          model: String.t(),
          base_stats: %{optional(String.t()) => integer()},
          rolled_stats: %{optional(String.t()) => integer()} | nil,
          rerolls_left: non_neg_integer(),
          race_picks: [String.t()],
          skills: %{optional(String.t()) => pos_integer()},
          edited: MapSet.t(atom())
        }
end
