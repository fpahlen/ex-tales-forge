defmodule TalesForge.Actions.PlayerMessage do
  @moduledoc """
  Phase 0 action: accept player text and append mock GM narration.
  Tier 1/2 LLM pipeline replaces this in Phase 1.
  """
  use Jido.Action,
    name: "player_message",
    description: "Process a player message in the current session",
    schema: [
      text: [type: :string, required: true]
    ]

  @impl true
  def run(%{text: text}, %{state: state}) do
    now = DateTime.utc_now()

    player_entry = %{
      id: System.unique_integer([:positive]),
      role: "player",
      text: String.trim(text),
      at: now
    }

    gm_entry = %{
      id: System.unique_integer([:positive]),
      role: "gm",
      text: mock_narration(text),
      at: now
    }

    entries = (state[:entries] || []) ++ [player_entry, gm_entry]
    turn_count = (state[:turn_count] || 0) + 1
    {:ok, %{turn_count: turn_count, entries: entries}}
  end

  defp mock_narration(text) do
    trimmed = String.trim(text)

    """
    The tavern air is thick with woodsmoke and murmured bets. You #{String.downcase(trimmed)}.

    Marta Kellen watches from behind the bar, measuring your intent. For now the world holds its breath — a fuller GM response will arrive once the two-tier LLM pipeline is wired in.
    """
    |> String.trim()
  end
end
