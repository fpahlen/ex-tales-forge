defmodule TalesForge.Game.Movement.PlaceHit do
  @moduledoc false

  # One place named after a lead-in word (TalesForge.Game.Movement): the place
  # id, its hops from where the character is, the byte position in the
  # lower-cased text and the term that matched.
  defstruct id: nil, hops: 0, pos: 0, term: ""
end
