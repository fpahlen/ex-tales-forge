defmodule TalesForge.GameCharacter.Moment do
  @moduledoc """
  A saved turn as character memory (`TalesForge.GameCharacter.MemoryLog.on_turn/1`)
  and the thought (`TalesForge.GameCharacter.Thought.for_turn/1`) see it: the
  session, the turn number, the turn's events, the world after the turn, the
  CHARACTER_MEMORY mode and `actor`, the slug of the character whose
  Intention the turn played (`TalesForge.Intention`). Neither asks who
  controls a character.
  """

  defstruct [:session_id, :turn_number, :actor, events: [], world: %{}, mode: :off]

  @typedoc "A saved turn, for memory and the thought."
  @type t :: %__MODULE__{
          session_id: Ecto.UUID.t(),
          turn_number: integer(),
          actor: String.t() | nil,
          events: [map()],
          world: map(),
          mode: :off | :shadow | :on
        }
end
