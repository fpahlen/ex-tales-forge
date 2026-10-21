defmodule TalesForge.World.Budget do
  @moduledoc false

  # The prompt lines so far (newest first) and the facts and characters they
  # use (TalesForge.World.prompt_lines/1).
  defstruct lines: [], count: 0, chars: 0
end
