defmodule TalesForge.World.AgentSpec do
  @moduledoc false

  # One agent a turn needs (TalesForge.World.collect/2): its id, its role in
  # the prompt (:here, :present, :held or :around) and its kind.
  defstruct id: nil, role: :here, kind: :location
end
