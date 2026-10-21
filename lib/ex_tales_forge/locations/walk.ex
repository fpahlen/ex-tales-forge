defmodule TalesForge.Locations.Walk do
  @moduledoc """
  A walk inside one grid (docs/design-locations.md, step 2). Pure.

  The target words resolve to an item on the grid
  (`TalesForge.Locations.Target`, the legend aliases); the character walks
  the shortest way next to it and ends facing it (`Move.approach/3`). Words
  for nothing on the grid, or an item it cannot reach, move nothing.
  """

  alias TalesForge.Locations.Grid
  alias TalesForge.Locations.Move
  alias TalesForge.Locations.Position
  alias TalesForge.Locations.Target

  @lead_in ~r/\b(?:over to|up to|across to|back to|to|toward|towards|into|by|near)\s+(.+)$/iu
  @articles ~r/^(?:the|a|an|that|this|my)\s+/iu

  @doc "Where a walk toward `words` ends: `{:moved, pos}`, or `{:no_move, words}`."
  @spec resolve(Grid.t(), Position.t(), String.t()) ::
          {:moved, Position.t()} | {:no_move, String.t()}
  def resolve(%Grid{} = grid, %Position{} = pos, words) do
    with {:ok, item} <- Target.resolve(grid, words),
         {:ok, to, _steps} <- Move.approach(grid, pos, item) do
      {:moved, to}
    else
      _none -> {:no_move, phrase(words)}
    end
  end

  @doc """
  The words of `text` that name where the character goes, for the note
  when there is no such thing here.

      iex> TalesForge.Locations.Walk.phrase("I walk over to the dragon.")
      "dragon"
      iex> TalesForge.Locations.Walk.phrase("dragon")
      "dragon"
  """
  @spec phrase(String.t()) :: String.t()
  def phrase(text) do
    words =
      case Regex.run(@lead_in, text, capture: :all_but_first) do
        [rest] -> rest
        nil -> text
      end

    words |> String.trim() |> String.trim_trailing(".") |> String.replace(@articles, "")
  end
end
