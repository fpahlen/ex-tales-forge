defmodule TalesForge.Game.ActionHandler.HandlerSpec do
  @moduledoc false

  # One row of the action handler table (TalesForge.Game.ActionHandler).
  # `handler` nil means the action type's name. `notes` is a template with
  # "%type", "%target" and "%ticks". `hints` names the state hints the row
  # gives. `skill?` says whether the result carries the skill.
  defstruct handler: nil, notes: "", hints: :none, skill?: false
end
