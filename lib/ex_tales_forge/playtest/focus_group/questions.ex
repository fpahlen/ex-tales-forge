defmodule TalesForge.Playtest.FocusGroup.Questions do
  @moduledoc """
  The fixed question bank for the persona focus group (call type: function).

  All personas get the same five questions. Each persona also gets one probe
  from the first bullet of its scorecard (`TalesForge.Playtest.Personas`).
  Ronny gets a red-team probe instead.
  """

  @bank [
    %{id: "good", text: "What felt good in your last session? Name one concrete moment."},
    %{id: "immersion", text: "What broke your immersion? Name the turn or the moment."},
    %{id: "improve", text: "What one change would make you want the next session more?"},
    %{id: "replay", text: "Which moment would you play again, and why?"},
    %{id: "quit", text: "What would make you quit Tales Forge? How close were you to that?"}
  ]

  @doc "The shared question bank, in the order we ask."
  @spec bank() :: [%{id: String.t(), text: String.t()}]
  def bank, do: @bank

  @doc """
  The questions for one persona: the bank plus at most one probe. The probe has
  the id `"probe"`.
  """
  @spec for_persona(map()) :: [%{id: String.t(), text: String.t()}]
  def for_persona(persona), do: @bank ++ probe(persona)

  @doc "The question ids for a persona. The typed reply must use these ids."
  @spec ids(map()) :: [String.t()]
  def ids(persona), do: Enum.map(for_persona(persona), & &1.id)

  defp probe(%{id: "ronny"}) do
    [
      %{
        id: "probe",
        text:
          "As the red team: which rule or limit was easiest to get around, and what should stop you next time?"
      }
    ]
  end

  defp probe(%{scorecard: [first | _]}) when is_binary(first) do
    [
      %{
        id: "probe",
        text: "Your scorecard says: \"#{first}\" How well did the last session do on this?"
      }
    ]
  end

  defp probe(_persona), do: []
end
